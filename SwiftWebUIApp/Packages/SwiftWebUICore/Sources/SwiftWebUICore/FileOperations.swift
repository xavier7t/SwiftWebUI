import Foundation

/// File operations scoped to a project's sources folder.
public struct FileOperations: Sendable {
    public let project: Project

    public init(project: Project) { self.project = project }

    private var fm: FileManager { .default }

    // MARK: Tree

    /// Reads the sources folder into a sorted tree (folders first, then files, case-insensitive).
    public func tree() throws -> [FileNode] {
        try Self.children(of: project.sourcesURL)
    }

    private static func children(of dir: URL) throws -> [FileNode] {
        let fm = FileManager.default
        let urls = try fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        let nodes: [FileNode] = try urls.map { url in
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
            return FileNode(url: url.standardizedFileURL, isDirectory: isDir,
                            children: isDir ? try children(of: url) : nil)
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    // MARK: Create

    @discardableResult
    public func createFile(named name: String, in folder: URL, contents: String = "") throws -> URL {
        let url = try destination(named: name, in: folder)
        do { try contents.write(to: url, atomically: true, encoding: .utf8) }
        catch { throw ProjectError.operationFailed("Could not create “\(name)”: \(error.localizedDescription)") }
        return url
    }

    @discardableResult
    public func createFolder(named name: String, in folder: URL) throws -> URL {
        let url = try destination(named: name, in: folder)
        do { try fm.createDirectory(at: url, withIntermediateDirectories: false) }
        catch { throw ProjectError.operationFailed("Could not create “\(name)”: \(error.localizedDescription)") }
        return url
    }

    // MARK: Rename / move / delete

    @discardableResult
    public func rename(_ item: URL, to newName: String) throws -> URL {
        try requireInside(item)
        guard fm.fileExists(atPath: item.path) else { throw ProjectError.notFound(item) }
        if newName == item.lastPathComponent { return item }
        let url = try destination(named: newName, in: item.deletingLastPathComponent())
        try perform("rename “\(item.lastPathComponent)”") { try fm.moveItem(at: item, to: url) }
        return url
    }

    @discardableResult
    public func move(_ item: URL, into folder: URL) throws -> URL {
        try requireInside(item)
        guard fm.fileExists(atPath: item.path) else { throw ProjectError.notFound(item) }
        let target = folder.standardizedFileURL
        let source = item.standardizedFileURL
        if target.path == source.path || target.path.hasPrefix(source.path + "/") {
            throw ProjectError.operationFailed("A folder can’t be moved into itself.")
        }
        let url = try destination(named: item.lastPathComponent, in: folder)
        try perform("move “\(item.lastPathComponent)”") { try fm.moveItem(at: item, to: url) }
        return url
    }

    /// Moves the item to the Trash.
    public func trash(_ item: URL) throws {
        try requireInside(item)
        guard fm.fileExists(atPath: item.path) else { throw ProjectError.notFound(item) }
        try perform("move “\(item.lastPathComponent)” to the Trash") {
            try fm.trashItem(at: item, resultingItemURL: nil)
        }
    }

    // MARK: Helpers

    /// Validates the name and folder, and returns the URL for a new item (which must not exist yet).
    private func destination(named name: String, in folder: URL) throws -> URL {
        try FileNameValidator.validate(name)
        try requireInside(folder, allowSources: true)
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: folder.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectError.notFound(folder)
        }
        let url = folder.appendingPathComponent(name).standardizedFileURL
        // Case-insensitive volumes: compare listing, not just fileExists.
        let siblings = (try? fm.contentsOfDirectory(atPath: folder.path)) ?? []
        if fm.fileExists(atPath: url.path) || siblings.contains(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            throw ProjectError.nameCollision(name)
        }
        return url
    }

    private func requireInside(_ url: URL, allowSources: Bool = false) throws {
        let base = project.sourcesURL.standardizedFileURL.resolvingSymlinksInPath().path
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path
        if path == base { if allowSources { return } else { throw ProjectError.outsideProject(url) } }
        guard path.hasPrefix(base + "/") else { throw ProjectError.outsideProject(url) }
    }

    private func perform(_ what: String, _ body: () throws -> Void) throws {
        do { try body() } catch let e as ProjectError { throw e }
        catch { throw ProjectError.operationFailed("Could not \(what): \(error.localizedDescription)") }
    }
}
