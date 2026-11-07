import Foundation

/// Errors raised by project loading and file operations, with user-facing messages.
public enum ProjectError: Error, Equatable, LocalizedError {
    case missingManifest(URL)
    case invalidManifest(URL, reason: String)
    case missingSourcesFolder(URL)
    case invalidName(String, reason: String)
    case nameCollision(String)
    case notFound(URL)
    case outsideProject(URL)
    case alreadyExists(URL)
    case operationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingManifest(let url):
            return "“\(url.lastPathComponent)” is not a SwiftWebUI project: \(ProjectManifest.fileName) is missing. Choose a project folder, or create a new project."
        case .invalidManifest(let url, let reason):
            return "The project manifest in “\(url.lastPathComponent)” is invalid: \(reason)"
        case .missingSourcesFolder(let url):
            return "The project “\(url.lastPathComponent)” has no sources folder. Create a folder with the name given in the manifest."
        case .invalidName(let name, let reason):
            return "“\(name)” is not a valid name: \(reason)"
        case .nameCollision(let name):
            return "An item named “\(name)” already exists in this location. Choose a different name."
        case .notFound(let url):
            return "“\(url.lastPathComponent)” no longer exists."
        case .outsideProject(let url):
            return "“\(url.lastPathComponent)” is outside the project folder."
        case .alreadyExists(let url):
            return "A project already exists at “\(url.lastPathComponent)”."
        case .operationFailed(let message):
            return message
        }
    }
}
