import Foundation

/// Creates and resolves bookmarks, so tests can replace the real security-scoped ones.
public protocol BookmarkProvider: Sendable {
    func makeBookmark(for url: URL) throws -> Data
    /// Returns the URL the bookmark points to and whether the bookmark should be recreated.
    func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool)
}

/// Security-scoped bookmarks, which let a sandboxed app reopen a folder after relaunch.
public struct SecurityScopedBookmarks: BookmarkProvider {
    public init() {}

    public func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    public func resolve(_ bookmark: Data) throws -> (url: URL, isStale: Bool) {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                          relativeTo: nil, bookmarkDataIsStale: &stale)
        return (url, stale)
    }
}

public struct RecentProject: Codable, Equatable, Identifiable, Sendable {
    public var path: String
    public var name: String
    public var bookmark: Data
    public var lastOpened: Date
    public var id: String { path }

    public init(path: String, name: String, bookmark: Data, lastOpened: Date) {
        self.path = path; self.name = name; self.bookmark = bookmark; self.lastOpened = lastOpened
    }
}

/// What reopening a recent project found.
public enum RecentProjectResolution: Equatable, Sendable {
    case available(URL)
    /// The folder is gone, moved, no longer a project, or its bookmark can't be resolved.
    case missing
}

/// The most recently opened projects, newest first, saved in `UserDefaults`.
public final class RecentProjectsStore: @unchecked Sendable {
    public static let defaultLimit = 10
    private static let key = "recentProjects"

    private let defaults: UserDefaults
    private let bookmarks: BookmarkProvider
    private let limit: Int
    private let lock = NSLock()

    public init(defaults: UserDefaults = .standard,
                bookmarks: BookmarkProvider = SecurityScopedBookmarks(),
                limit: Int = RecentProjectsStore.defaultLimit) {
        self.defaults = defaults; self.bookmarks = bookmarks; self.limit = max(1, limit)
    }

    /// Newest first.
    public var items: [RecentProject] {
        lock.lock(); defer { lock.unlock() }
        return load()
    }

    /// Moves (or adds) the project to the top, dropping the oldest beyond the limit.
    public func add(_ project: Project, now: Date = Date()) throws {
        let bookmark = try bookmarks.makeBookmark(for: project.root)
        lock.lock(); defer { lock.unlock() }
        var list = load().filter { $0.path != project.root.path }
        list.insert(RecentProject(path: project.root.path, name: project.name,
                                  bookmark: bookmark, lastOpened: now), at: 0)
        save(Array(list.prefix(limit)))
    }

    public func remove(_ item: RecentProject) {
        lock.lock(); defer { lock.unlock() }
        save(load().filter { $0.path != item.path })
    }

    public func removeAll() {
        lock.lock(); defer { lock.unlock() }
        save([])
    }

    /// Resolves the bookmark and checks the project is still there. A stale bookmark is renewed in place.
    /// The caller starts security-scoped access on the returned URL.
    public func resolve(_ item: RecentProject, fileManager: FileManager = .default) -> RecentProjectResolution {
        guard let (url, stale) = try? bookmarks.resolve(item.bookmark) else { return .missing }
        let manifest = url.appendingPathComponent(ProjectManifest.fileName).path
        guard fileManager.fileExists(atPath: manifest) else { return .missing }
        if stale || url.path != item.path, let fresh = try? bookmarks.makeBookmark(for: url) {
            lock.lock(); defer { lock.unlock() }
            var list = load()
            if let i = list.firstIndex(where: { $0.id == item.id }) {
                list[i] = RecentProject(path: url.path, name: item.name, bookmark: fresh, lastOpened: item.lastOpened)
                save(list)
            }
        }
        return .available(url)
    }

    /// Whether the project can still be found, without changing anything.
    public func isMissing(_ item: RecentProject, fileManager: FileManager = .default) -> Bool {
        guard let (url, _) = try? bookmarks.resolve(item.bookmark) else { return true }
        return !fileManager.fileExists(atPath: url.appendingPathComponent(ProjectManifest.fileName).path)
    }

    private func load() -> [RecentProject] {
        guard let data = defaults.data(forKey: Self.key),
              let list = try? JSONDecoder().decode([RecentProject].self, from: data) else { return [] }
        return list
    }

    private func save(_ list: [RecentProject]) {
        defaults.set(try? JSONEncoder().encode(list), forKey: Self.key)
    }
}
