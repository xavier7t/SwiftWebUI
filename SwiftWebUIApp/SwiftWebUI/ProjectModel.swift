import SwiftUI
import SwiftWebUICore

/// UI-facing state for the open project: the file tree, selection and error messages.
@MainActor @Observable
final class ProjectModel {
    private(set) var project: Project?
    private(set) var tree: [FileNode] = []
    var selection: URL? { didSet { if selection != oldValue { openSession() } } }
    /// The open file's editing session, or nil when nothing editable is selected.
    private(set) var session: OpenFileSession?
    /// Set when the open file changed on disk while it has unsaved edits.
    var conflictFileName: String?
    /// Non-nil when the selected file cannot be opened as text.
    private(set) var openError: String?
    var errorMessage: String?
    /// Item currently being renamed inline, or a pending new item name prompt.
    var renaming: URL?
    /// Live preview pipeline; fed by the open file's changes.
    let preview = PreviewModel()
    /// Asks the editor to move the caret to a position in the open file.
    private(set) var revealRequest: RevealRequest?

    /// Asks the editor to insert code at the caret.
    private(set) var insertRequest: InsertRequest?

    struct InsertRequest: Equatable {
        let id = UUID()
        let text: String
    }

    var canInsert: Bool { session != nil }

    func insert(_ snippet: String) {
        guard session != nil else { return }
        insertRequest = InsertRequest(text: snippet)
    }

    struct RevealRequest: Equatable {
        let id = UUID()
        let line: Int
        let column: Int
    }

    private var watcher: ProjectWatcher?
    private var accessedRoot: URL?
    private var previewTask: Task<Void, Never>?

    var operations: FileOperations? { project.map(FileOperations.init) }

    // MARK: Open / create

    func open(_ root: URL) {
        do {
            let scoped = root.startAccessingSecurityScopedResource()
            let project = try Project.load(at: root)
            close()
            if scoped { accessedRoot = root }
            self.project = project
            reload()
            startWatching()
            selection = tree.flatMap(Self.flatten).first { !$0.isDirectory }?.url
            schedulePreview()
        } catch {
            root.stopAccessingSecurityScopedResource()
            report(error)
        }
    }

    func create(name: String, in location: URL) {
        let scoped = location.startAccessingSecurityScopedResource()
        defer { if scoped { location.stopAccessingSecurityScopedResource() } }
        do {
            let project = try Project.create(name: name, in: location)
            open(project.root)
        } catch { report(error) }
    }

    func close() {
        watcher?.stop(); watcher = nil
        accessedRoot?.stopAccessingSecurityScopedResource(); accessedRoot = nil
        saveCurrent()
        previewTask?.cancel(); previewTask = nil
        preview.reset()
        revealRequest = nil
        project = nil; tree = []; selection = nil; session = nil
    }

    // MARK: Export

    /// The outcome of the last export, shown in an alert.
    enum ExportOutcome: Identifiable {
        case done(ExportReport)
        case failed(String)
        var id: String {
            switch self { case .done(let r): "done-\(r.destination.path)"; case .failed(let m): "failed-\(m)" }
        }
    }
    var exportOutcome: ExportOutcome?

    /// Asks for a folder and writes the project there as a static site.
    func exportSite() {
        guard let project else { return }
        saveCurrent()
        let panel = NSOpenPanel()
        panel.message = "Choose a folder for the exported site"
        panel.prompt = "Export"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        let scoped = folder.startAccessingSecurityScopedResource()
        defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
        do {
            exportOutcome = .done(try SiteExporter.export(project: project, to: folder))
        } catch {
            exportOutcome = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
        }
    }

    /// `true` when the project has no source files at all.
    var isEmptyProject: Bool { project != nil && !tree.flatMap(Self.flatten).contains { !$0.isDirectory } }

    // MARK: Editor session

    /// Saves any pending edits in the open file.
    func saveCurrent() { session?.save() }

    private func openSession() {
        session?.save()
        previewTask?.cancel(); previewTask = nil
        session = nil
        openError = nil
        conflictFileName = nil
        guard let url = selection else { return }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { return }
        do {
            let s = try OpenFileSession(url: url)
            s.onSaveError = { [weak self] in self?.report($0) }
            s.onExternalChange = { [weak self] change in
                guard let self else { return }
                switch change {
                case .conflict: self.conflictFileName = url.lastPathComponent
                case .deleted: break // reload() clears the selection
                case .reloaded: break
                }
            }
            session = s
            // Every change to the open file, starting with its current text, goes to the preview.
            previewTask = Task { [weak self] in
                for await text in s.changes() {
                    guard let self else { return }
                    self.schedulePreview(text: text)
                }
            }
        } catch {
            openError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func resolveConflict(keepMine: Bool) {
        if keepMine { session?.keepEditorVersion() } else { session?.reloadFromDisk() }
        conflictFileName = nil
    }

    // MARK: Preview and problems

    /// Path of `url` relative to the sources folder when it is a Swift file the parser reads.
    private func sourcePath(of url: URL) -> String? {
        guard let project, url.pathExtension == "swift" else { return nil }
        let base = project.sourcesURL.standardizedFileURL.path + "/"
        let path = url.standardizedFileURL.path
        return path.hasPrefix(base) ? String(path.dropFirst(base.count)) : nil
    }

    /// Re-renders the preview, using the open file's unsaved text when it is part of the project's sources.
    func schedulePreview(text: String? = nil) {
        guard let project else { return }
        var override: (path: String, text: String)?
        if let session, let path = sourcePath(of: session.url) { override = (path, text ?? session.text) }
        preview.requestRender(project: project, override: override)
    }

    /// Problems in the open file, for underlines and gutter marks in the editor.
    var openFileDiagnostics: [Diagnostic] {
        guard let session, let path = sourcePath(of: session.url) else { return [] }
        return preview.diagnostics.filter { $0.location.file == path }
    }

    /// Opens the file a problem is in and moves the caret to it.
    func reveal(_ diagnostic: Diagnostic) {
        guard let project else { return }
        let url = project.sourcesURL.appendingPathComponent(diagnostic.location.file).standardizedFileURL
        if selection?.standardizedFileURL != url { selection = url }
        revealRequest = RevealRequest(line: diagnostic.location.line, column: diagnostic.location.column)
    }

    // MARK: File operations

    func createFile(named name: String, in folder: URL?) {
        run { ops in
            let url = try ops.createFile(named: name, in: folder ?? ops.project.sourcesURL,
                                         contents: "import SwiftUI\n\n")
            self.reload(); self.selection = url
        }
    }

    func createFolder(named name: String, in folder: URL?) {
        run { ops in
            _ = try ops.createFolder(named: name, in: folder ?? ops.project.sourcesURL)
            self.reload()
        }
    }

    func rename(_ item: URL, to name: String) {
        run { ops in
            let new = try ops.rename(item, to: name)
            if self.selection == item { self.selection = new }
            self.reload()
        }
    }

    func trash(_ item: URL) {
        run { ops in
            try ops.trash(item)
            if let sel = self.selection, sel.path == item.path || sel.path.hasPrefix(item.path + "/") {
                self.selection = nil
            }
            self.reload()
        }
    }

    func move(_ item: URL, into folder: URL) {
        run { ops in
            let new = try ops.move(item, into: folder)
            if self.selection == item { self.selection = new }
            self.reload()
        }
    }

    // MARK: Refresh

    func reload() {
        guard let ops = operations else { return }
        session?.checkForExternalChange()
        do { tree = try ops.tree() } catch { tree = [] }
        if let sel = selection, !FileManager.default.fileExists(atPath: sel.path) { selection = nil }
        schedulePreview() // other files may have been added, removed or edited
    }

    private func startWatching() {
        guard let root = project?.root else { return }
        watcher = ProjectWatcher(url: root) { [weak self] in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Helpers

    private func run(_ body: (FileOperations) throws -> Void) {
        guard let ops = operations else { return }
        do { try body(ops) } catch { report(error) }
    }

    private func report(_ error: Error) {
        errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    static func flatten(_ node: FileNode) -> [FileNode] {
        [node] + (node.children ?? []).flatMap(flatten)
    }
}
