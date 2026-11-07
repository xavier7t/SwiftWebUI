import Foundation

/// A file or folder in the project's sources tree.
public struct FileNode: Identifiable, Hashable, Sendable {
    public let url: URL
    public let isDirectory: Bool
    /// `nil` for files; sorted children for folders.
    public var children: [FileNode]?

    public var id: URL { url }
    public var name: String { url.lastPathComponent }

    public init(url: URL, isDirectory: Bool, children: [FileNode]? = nil) {
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }
}
