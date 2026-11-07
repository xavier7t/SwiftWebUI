import Foundation

/// The small manifest file (`swiftwebui.json`) at the root of a project folder.
public struct ProjectManifest: Codable, Equatable, Sendable {
    public static let fileName = "swiftwebui.json"
    public static let defaultSourcesFolder = "Sources"
    public static let defaultEntryView = "ContentView"

    public var name: String
    /// Folder (relative to the project root) holding the Swift source files.
    public var sources: String
    /// Name of the `View` struct that is rendered as the page.
    public var entryView: String

    public init(name: String, sources: String = defaultSourcesFolder, entryView: String = defaultEntryView) {
        self.name = name
        self.sources = sources
        self.entryView = entryView
    }
}
