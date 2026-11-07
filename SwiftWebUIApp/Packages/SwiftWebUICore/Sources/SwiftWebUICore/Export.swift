import Foundation

/// What an export wrote, and what it could not include.
public struct ExportReport: Equatable, Sendable {
    public let destination: URL
    /// Paths of the written files, relative to `destination`.
    public let files: [String]
    /// Image names the code refers to that don't exist in the project. They are left as broken images.
    public let missingImages: [String]
    /// Warnings from parsing and rendering.
    public let warnings: [Diagnostic]
}

public enum ExportError: Error, Equatable, LocalizedError {
    case hasErrors([Diagnostic])
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .hasErrors(let list):
            let first = list.first { $0.severity == .error }
            let detail = first.map { " First problem: \($0.message) (\($0.location))." } ?? ""
            return "The project has errors, so it can’t be exported yet. Fix them and try again.\(detail)"
        case .failed(let message):
            return "The export failed: \(message)"
        }
    }
}

/// Writes a project as a static website: `index.html`, `styles.css`, `runtime.js` and an `assets` folder.
public enum SiteExporter {
    public static let assetsFolder = "assets"

    public static func export(project: Project, to destination: URL, fileManager: FileManager = .default) throws -> ExportReport {
        let parsed = ProjectParser.parse(project: project, fileManager: fileManager)
        guard let tree = parsed.tree, !parsed.hasErrors else { throw ExportError.hasErrors(parsed.diagnostics) }

        let collector = AssetCollector(project: project, fileManager: fileManager)
        let output = HTMLRenderer.render(tree, options: RenderOptions(assetResolver: { collector.resolve($0) }))
        let files = PageTemplate.exportFiles(output, title: project.name)

        var written: [String] = []
        do {
            try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            for (path, text) in files.sorted(by: { $0.key < $1.key }) {
                try text.write(to: destination.appendingPathComponent(path), atomically: true, encoding: .utf8)
                written.append(path)
            }
            let (copies, _) = collector.result()
            if !copies.isEmpty {
                let folder = destination.appendingPathComponent(assetsFolder, isDirectory: true)
                try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
                for (name, source) in copies.sorted(by: { $0.key < $1.key }) {
                    let target = folder.appendingPathComponent(name)
                    if fileManager.fileExists(atPath: target.path) { try fileManager.removeItem(at: target) }
                    try fileManager.copyItem(at: source, to: target)
                    written.append("\(assetsFolder)/\(name)")
                }
            }
        } catch {
            throw ExportError.failed(error.localizedDescription)
        }
        return ExportReport(destination: destination, files: written, missingImages: collector.result().missing,
                            warnings: (parsed.diagnostics + output.diagnostics).filter { $0.severity == .warning })
    }

    /// Decides the exported name of each image and remembers which are missing.
    private final class AssetCollector: @unchecked Sendable {
        private let project: Project
        private let fileManager: FileManager
        private let lock = NSLock()
        private var bySource: [String: String] = [:]   // source path -> exported file name
        private var copies: [String: URL] = [:]        // exported file name -> source
        private var missing: [String] = []

        init(project: Project, fileManager: FileManager) {
            self.project = project
            self.fileManager = fileManager
        }

        func resolve(_ name: String) -> String? {
            lock.lock(); defer { lock.unlock() }
            guard let source = ProjectAssets.file(named: name, in: project, fileManager: fileManager) else {
                if !missing.contains(name) { missing.append(name) }
                return nil
            }
            let exported: String
            if let known = bySource[source.path] {
                exported = known
            } else {
                var candidate = source.lastPathComponent
                var n = 2
                while copies[candidate] != nil {
                    candidate = "\(source.deletingPathExtension().lastPathComponent)-\(n).\(source.pathExtension)"
                    n += 1
                }
                bySource[source.path] = candidate
                copies[candidate] = source
                exported = candidate
            }
            let encoded = exported.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? exported
            return "\(assetsFolder)/\(encoded)"
        }

        func result() -> (copies: [String: URL], missing: [String]) {
            lock.lock(); defer { lock.unlock() }
            return (copies, missing)
        }
    }
}

extension PageTemplate {
    /// The files of an exported site, keyed by path. Unlike the preview, the page has no host or server:
    /// it links its own style and script, and the script starts with the rendered `@State` values.
    static func exportFiles(_ output: RenderOutput, title: String) -> [String: String] {
        let index = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>\(HTMLElement.escapeText(title))</title>
        <link rel="stylesheet" href="styles.css">
        </head>
        <body>
        <div id="root">\(output.html)</div>
        <script src="runtime.js"></script>
        <script>swui.update(null, \(scriptSafe(output.statesJSON)));</script>
        </body>
        </html>

        """
        return ["index.html": index, "styles.css": css + "\n", "runtime.js": runtime + "\n"]
    }
}
