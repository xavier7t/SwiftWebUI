import Foundation

/// A position in a project source file. Lines and columns are 1-based; columns count characters.
public struct CodeLocation: Equatable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let file: String
    public let line: Int
    public let column: Int

    public init(file: String, line: Int, column: Int) {
        self.file = file
        self.line = line
        self.column = column
    }

    public var description: String { "\(file):\(line):\(column)" }

    public static func < (a: CodeLocation, b: CodeLocation) -> Bool {
        (a.file, a.line, a.column) < (b.file, b.line, b.column)
    }
}

/// A constant or reference that appears as an argument in the view tree.
public indirect enum Value: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([Value])
    /// An implicit or qualified member such as `.largeTitle`, `Color.red` or `.system(size: 20)`.
    case member(base: String?, name: String, arguments: [Argument])
    /// A method called on a member value, such as `.white.opacity(0.8)`.
    case method(Value, name: String, arguments: [Argument])
    /// A reference to a `@State` variable, by its unique id.
    case state(String)
    /// A string containing interpolated `@State` references.
    case interpolated([TextPart])
}

public struct Argument: Equatable, Sendable {
    public let label: String?
    public let value: Value

    public init(label: String? = nil, value: Value) {
        self.label = label
        self.value = value
    }
}

public enum TextPart: Equatable, Sendable {
    case literal(String)
    case state(String)
}

/// A state change performed by a `Button`.
public enum Action: Equatable, Sendable {
    case add(state: String, amount: Double)
    case set(state: String, value: Value)
    case toggle(state: String)
}

public struct ModifierNode: Equatable, Sendable {
    public let name: String
    public let arguments: [Argument]
    public let location: CodeLocation

    public init(name: String, arguments: [Argument], location: CodeLocation) {
        self.name = name
        self.arguments = arguments
        self.location = location
    }
}

public struct StateVariable: Equatable, Sendable {
    /// Unique across the tree, e.g. `ContentView.count` or `Counter#2.count`.
    public let id: String
    public let name: String
    public let initial: Value
    public let location: CodeLocation
}

public struct ViewNode: Equatable, Sendable {
    /// A built-in view name (`VStack`, `Text`, …) or the name of a custom `View` struct.
    public var kind: String
    /// `true` when `kind` is a user-defined struct; its single child is the expanded `body`.
    public var isCustom: Bool
    public var arguments: [Argument]
    public var modifiers: [ModifierNode]
    public var children: [ViewNode]
    public var actions: [Action]
    public var location: CodeLocation

    public init(kind: String, isCustom: Bool = false, arguments: [Argument] = [], modifiers: [ModifierNode] = [],
                children: [ViewNode] = [], actions: [Action] = [], location: CodeLocation) {
        self.kind = kind
        self.isCustom = isCustom
        self.arguments = arguments
        self.modifiers = modifiers
        self.children = children
        self.actions = actions
        self.location = location
    }
}

/// The result of parsing a project: the entry view expanded into a tree, plus its `@State` variables.
public struct ViewTree: Equatable, Sendable {
    public var root: ViewNode
    public var states: [StateVariable]
}

// MARK: - Compact text form (used by tests and debugging)

extension Value: CustomStringConvertible {
    public var description: String {
        switch self {
        case .string(let s): return "\"\(s)\""
        case .number(let n): return formatNumber(n)
        case .bool(let b): return b ? "true" : "false"
        case .array(let items): return "[" + items.map(\.description).joined(separator: ", ") + "]"
        case .member(let base, let name, let args):
            return (base ?? "") + "." + name + (args.isEmpty ? "" : "(" + args.map(\.description).joined(separator: ", ") + ")")
        case .method(let value, let name, let args):
            return value.description + "." + name + "(" + args.map(\.description).joined(separator: ", ") + ")"
        case .state(let id): return "$" + id
        case .interpolated(let parts):
            return "\"" + parts.map {
                switch $0 {
                case .literal(let s): return s
                case .state(let id): return "\\($" + id + ")"
                }
            }.joined() + "\""
        }
    }
}

extension Argument: CustomStringConvertible {
    public var description: String { (label.map { $0 + ": " } ?? "") + value.description }
}

extension Action: CustomStringConvertible {
    public var description: String {
        switch self {
        case .add(let s, let n): return "$\(s) += \(formatNumber(n))"
        case .set(let s, let v): return "$\(s) = \(v)"
        case .toggle(let s): return "$\(s).toggle()"
        }
    }
}

extension ViewNode {
    /// One line per node, indented by depth, with modifiers inline, e.g. `Text("Hi") .font(.title)`.
    public var outline: String { outlineLines(depth: 0).joined(separator: "\n") }

    private func outlineLines(depth: Int) -> [String] {
        var head = String(repeating: "  ", count: depth) + kind
        if !arguments.isEmpty { head += "(" + arguments.map(\.description).joined(separator: ", ") + ")" }
        if isCustom { head += " [custom]" }
        for m in modifiers {
            head += " ." + m.name + "(" + m.arguments.map(\.description).joined(separator: ", ") + ")"
        }
        if !actions.isEmpty { head += " {" + actions.map(\.description).joined(separator: "; ") + "}" }
        return [head] + children.flatMap { $0.outlineLines(depth: depth + 1) }
    }
}

func formatNumber(_ n: Double) -> String {
    if n.isFinite, n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
    return String(n)
}
