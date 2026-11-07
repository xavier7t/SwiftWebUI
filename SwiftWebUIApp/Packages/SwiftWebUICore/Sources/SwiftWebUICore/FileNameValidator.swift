import Foundation

public enum FileNameValidator {
    /// Throws `ProjectError.invalidName` if `name` can't be used as a single file or folder name.
    public static func validate(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { throw ProjectError.invalidName(name, reason: "the name is empty.") }
        if trimmed != name { throw ProjectError.invalidName(name, reason: "it starts or ends with a space.") }
        if name == "." || name == ".." { throw ProjectError.invalidName(name, reason: "reserved name.") }
        if name.contains("/") || name.contains(":") || name.contains("\0") {
            throw ProjectError.invalidName(name, reason: "it can’t contain “/” or “:”.")
        }
        if name.utf8.count > 255 { throw ProjectError.invalidName(name, reason: "it is too long.") }
    }
}
