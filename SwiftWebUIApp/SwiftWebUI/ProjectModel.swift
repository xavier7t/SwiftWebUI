import SwiftUI
import SwiftWebUICore

/// UI-facing state for the open project: the file tree, selection and error messages.
@MainActor @Observable
final class ProjectModel {
    private(set) var project: Project?
    private(set) var tree: [FileNode] = []
    var selection: URL?
    var errorMessage: String?
    /// Item currently being renamed inline, or a pending new item name prompt.
    var renaming: URL?

    private var watcher: ProjectWatcher?
    private var accessedRoot: URL?

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
        project = nil; tree = []; selection = nil
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
        do { tree = try ops.tree() } catch { tree = [] }
        if let sel = selection, !FileManager.default.fileExists(atPath: sel.path) { selection = nil }
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
