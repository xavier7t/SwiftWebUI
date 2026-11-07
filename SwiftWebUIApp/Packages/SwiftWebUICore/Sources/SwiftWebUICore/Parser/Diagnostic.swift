import Foundation

public enum DiagnosticCode: String, Sendable, Equatable, CaseIterable {
    case syntaxError
    case unsupportedSyntax
    case unknownView
    case unknownModifier
    case unknownArgument
    case missingArgument
    case invalidArgument
    case unknownName
    case circularReference
    case missingEntryView
    case duplicateView
    case unreadableFile
    case invalidState
}

/// A problem found while building the view tree, with a position and a hint for fixing it.
public struct Diagnostic: Equatable, Hashable, Sendable, CustomStringConvertible {
    public enum Severity: String, Sendable { case error, warning }

    public let severity: Severity
    public let code: DiagnosticCode
    public let message: String
    /// What the user can do next, when there is a useful suggestion.
    public let suggestion: String?
    public let location: CodeLocation

    public init(severity: Severity = .error, code: DiagnosticCode, message: String,
                suggestion: String? = nil, location: CodeLocation) {
        self.severity = severity
        self.code = code
        self.message = message
        self.suggestion = suggestion
        self.location = location
    }

    /// Message followed by the suggestion, for display.
    public var fullMessage: String { suggestion.map { "\(message) \($0)" } ?? message }

    public var description: String { "\(location): \(severity.rawValue): \(fullMessage)" }
}

public struct ParseResult: Sendable {
    /// `nil` only when the entry view could not be found at all. Otherwise a tree with the valid parts.
    public let tree: ViewTree?
    public let diagnostics: [Diagnostic]

    public var errors: [Diagnostic] { diagnostics.filter { $0.severity == .error } }
    public var hasErrors: Bool { diagnostics.contains { $0.severity == .error } }
}

/// A Swift source file handed to the parser.
public struct SourceFile: Equatable, Sendable {
    public let path: String
    public let text: String

    public init(path: String, text: String) {
        self.path = path
        self.text = text
    }
}

enum Suggest {
    /// The closest candidate to `name`, if it is close enough to be a likely typo.
    static func closest(to name: String, in candidates: [String]) -> String? {
        let lower = name.lowercased()
        var best: (String, Int)?
        for c in candidates {
            let d = c.lowercased() == lower ? 0 : distance(lower, c.lowercased())
            if best == nil || d < best!.1 { best = (c, d) }
        }
        guard let (candidate, d) = best, d <= max(1, min(3, (name.count + 1) / 3)) else { return nil }
        return candidate
    }

    static func distance(_ a: String, _ b: String) -> Int {
        let a = Array(a), b = Array(b)
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var prev = Array(0...b.count)
        for i in 1...a.count {
            var cur = [i] + Array(repeating: 0, count: b.count)
            for j in 1...b.count {
                cur[j] = min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (a[i - 1] == b[j - 1] ? 0 : 1))
            }
            prev = cur
        }
        return prev[b.count]
    }
}
