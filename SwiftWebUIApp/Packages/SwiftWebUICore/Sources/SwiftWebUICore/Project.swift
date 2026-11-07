import Foundation

/// A SwiftWebUI project on disk: a folder with a manifest and a sources folder.
public struct Project: Equatable, Sendable {
    public let root: URL
    public let manifest: ProjectManifest

    public var sourcesURL: URL { root.appendingPathComponent(manifest.sources, isDirectory: true) }
    public var name: String { manifest.name }

    public init(root: URL, manifest: ProjectManifest) {
        self.root = root.standardizedFileURL
        self.manifest = manifest
    }

    // MARK: Loading

    public static func load(at root: URL, fileManager: FileManager = .default) throws -> Project {
        let root = root.standardizedFileURL
        let manifestURL = root.appendingPathComponent(ProjectManifest.fileName)
        guard fileManager.fileExists(atPath: manifestURL.path) else {
            throw ProjectError.missingManifest(root)
        }
        let manifest: ProjectManifest
        do {
            manifest = try JSONDecoder().decode(ProjectManifest.self, from: Data(contentsOf: manifestURL))
        } catch let error as DecodingError {
            throw ProjectError.invalidManifest(root, reason: Self.describe(error))
        } catch {
            throw ProjectError.invalidManifest(root, reason: error.localizedDescription)
        }
        guard Self.isSafeRelativePath(manifest.sources) else {
            throw ProjectError.invalidManifest(root, reason: "“sources” must be a folder inside the project.")
        }
        let project = Project(root: root, manifest: manifest)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: project.sourcesURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw ProjectError.missingSourcesFolder(root)
        }
        return project
    }

    // MARK: Creation

    /// Creates `<location>/<name>` with a manifest, a sources folder and an entry view file.
    @discardableResult
    public static func create(name: String, in location: URL, template: ProjectTemplate = .blank,
                              fileManager: FileManager = .default) throws -> Project {
        try FileNameValidator.validate(name)
        let root = location.appendingPathComponent(name, isDirectory: true).standardizedFileURL
        if fileManager.fileExists(atPath: root.appendingPathComponent(ProjectManifest.fileName).path) {
            throw ProjectError.alreadyExists(root)
        }
        if fileManager.fileExists(atPath: root.path) {
            throw ProjectError.nameCollision(name)
        }
        let manifest = ProjectManifest(name: name)
        let project = Project(root: root, manifest: manifest)
        do {
            try fileManager.createDirectory(at: project.sourcesURL, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(manifest).write(to: root.appendingPathComponent(ProjectManifest.fileName))
            for (path, text) in template.files {
                let url = project.sourcesURL.appendingPathComponent(path)
                try fileManager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try text.write(to: url, atomically: true, encoding: .utf8)
            }
        } catch {
            throw ProjectError.operationFailed("Could not create the project: \(error.localizedDescription)")
        }
        return project
    }

    public static let defaultEntrySource = """
    import SwiftUI

    struct ContentView: View {
        var body: some View {
            VStack {
                Text("Hello, SwiftWebUI")
                    .font(.largeTitle)
            }
            .padding()
        }
    }

    """

    // MARK: Helpers

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty, !path.hasPrefix("/") else { return false }
        return !path.split(separator: "/").contains("..")
    }

    private static func describe(_ error: DecodingError) -> String {
        switch error {
        case .keyNotFound(let key, _): return "missing “\(key.stringValue)”."
        case .typeMismatch(_, let ctx), .valueNotFound(_, let ctx), .dataCorrupted(let ctx):
            let path = ctx.codingPath.map(\.stringValue).joined(separator: ".")
            return path.isEmpty ? "not valid JSON." : "“\(path)” has the wrong type."
        @unknown default: return "unreadable."
        }
    }
}
