import Foundation

/// Finds the files `Image("name")` refers to inside a project.
public enum ProjectAssets {
    private static let extensions = ["png", "jpg", "jpeg", "gif", "svg", "webp"]
    private static let maxBytes = 5_000_000

    private static let mimeTypes = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                    "gif": "image/gif", "svg": "image/svg+xml", "webp": "image/webp"]

    /// The file for an image name, looked up in the project root, `Assets`, `Resources` and the sources folder.
    public static func file(named name: String, in project: Project, fileManager: FileManager = .default) -> URL? {
        guard ProjectAssets.isSafe(name) else { return nil }
        let folders = [project.root, project.root.appendingPathComponent("Assets"),
                       project.root.appendingPathComponent("Resources"), project.sourcesURL]
        let hasExtension = extensions.contains((name as NSString).pathExtension.lowercased())
        let candidates = hasExtension ? [name] : extensions.map { "\(name).\($0)" }
        for folder in folders {
            for candidate in candidates {
                let url = folder.appendingPathComponent(candidate)
                var isDir: ObjCBool = false
                if fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue { return url }
            }
        }
        return nil
    }

    /// A resolver for `RenderOptions` that inlines project images as data URIs, so the page needs no file access.
    public static func resolver(for project: Project) -> @Sendable (String) -> String? {
        let cache = Cache()
        return { name in
            guard let url = file(named: name, in: project) else { return nil }
            return cache.dataURI(for: url)
        }
    }

    static func isSafe(_ name: String) -> Bool {
        !name.isEmpty && !name.hasPrefix("/") && !name.split(separator: "/").contains("..")
    }

    private final class Cache: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String: (modified: Date?, uri: String?)] = [:]

        func dataURI(for url: URL) -> String? {
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            lock.lock(); defer { lock.unlock() }
            if let e = entries[url.path], e.modified == modified { return e.uri }
            var uri: String?
            if let data = try? Data(contentsOf: url), data.count <= ProjectAssets.maxBytes,
               let mime = ProjectAssets.mimeTypes[url.pathExtension.lowercased()] {
                uri = "data:\(mime);base64,\(data.base64EncodedString())"
            }
            entries[url.path] = (modified, uri)
            return uri
        }
    }
}
