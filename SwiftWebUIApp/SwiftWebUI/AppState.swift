import SwiftUI
import AppKit
import SwiftWebUICore

/// App-wide state: recent projects, sandbox access to open projects, and window bookkeeping.
@MainActor @Observable
final class AppState {
    static let shared = AppState()

    let recentsStore: RecentProjectsStore
    private(set) var recents: [RecentProject] = []
    /// Recent projects that can no longer be found.
    private(set) var missing: Set<String> = []
    /// Shown in an alert on the welcome window.
    var errorMessage: String?
    /// Set by File > New Project…; the welcome window shows the new project sheet and clears it.
    var wantsNewProject = false

    /// Security-scoped URLs held for open projects, by path. Window values lose the scope, so it is kept here.
    @ObservationIgnored private var held: [String: URL] = [:]
    private(set) var openProjectWindows = 0
    @ObservationIgnored var isTerminating = false

    init(store: RecentProjectsStore = RecentProjectsStore()) {
        recentsStore = store
        refreshRecents()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in AppState.shared.isTerminating = true }
        }
    }

    func refreshRecents() {
        recents = recentsStore.items
        missing = Set(recents.filter { recentsStore.isMissing($0) }.map(\.path))
    }

    func removeRecent(_ item: RecentProject) {
        recentsStore.remove(item)
        refreshRecents()
    }

    func clearRecents() {
        recentsStore.removeAll()
        refreshRecents()
    }

    // MARK: Opening

    /// Validates a folder the user picked, remembers it and returns it ready to open in a window.
    func prepareToOpen(_ url: URL) -> URL? {
        let scoped = url.startAccessingSecurityScopedResource()
        do {
            let project = try Project.load(at: url)
            if scoped { held[project.root.path] = url }
            try? recentsStore.add(project)
            refreshRecents()
            return project.root
        } catch {
            if scoped { url.stopAccessingSecurityScopedResource() }
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    /// Reopens a recent project through its bookmark. Returns nil and reports when it is missing.
    func prepareToOpen(_ item: RecentProject) -> URL? {
        switch recentsStore.resolve(item) {
        case .missing:
            refreshRecents()
            errorMessage = "“\(item.name)” can’t be found. It may have been moved or deleted. You can remove it from the list."
            return nil
        case .available(let url):
            return prepareToOpen(url)
        }
    }

    /// Makes sure the sandbox lets a restored project window read its folder, using the recents bookmark.
    func ensureAccess(to root: URL) -> Bool {
        if held[root.path] != nil || FileManager.default.isReadableFile(atPath: root.appendingPathComponent(ProjectManifest.fileName).path) {
            return true
        }
        guard let item = recentsStore.items.first(where: { $0.path == root.path }),
              case .available(let url) = recentsStore.resolve(item) else { return false }
        if url.startAccessingSecurityScopedResource() { held[url.standardizedFileURL.path] = url }
        return true
    }

    // MARK: Panels

    func chooseProjectFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose a SwiftWebUI project folder"
        panel.prompt = "Open"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    func chooseLocation() -> URL? {
        let panel = NSOpenPanel()
        panel.message = "Choose where to create the project"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Creates a project in `location` and prepares it to open.
    func createProject(name: String, in location: URL) -> URL? {
        let scoped = location.startAccessingSecurityScopedResource()
        defer { if scoped { location.stopAccessingSecurityScopedResource() } }
        do {
            let project = try Project.create(name: name, in: location)
            // The new folder is inside `location`, whose access ends here, so keep it open through its own scope.
            if scoped { held[project.root.path] = location; _ = location.startAccessingSecurityScopedResource() }
            try? recentsStore.add(project)
            refreshRecents()
            return project.root
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    // MARK: Windows

    func projectWindowAppeared() { openProjectWindows += 1 }
    func projectWindowDisappeared() { openProjectWindows = max(0, openProjectWindows - 1) }
}
