import Foundation

/// The in-app reference of supported views and modifiers. It is generated from `Registry`, so it can't drift.
public struct ReferenceEntry: Equatable, Sendable, Identifiable {
    public var id: String { section + "/" + name }
    public let section: String
    public let name: String
    public let summary: String
    public let example: String
    public let arguments: [ArgumentSpec]
}

public enum Reference {
    public static var entries: [ReferenceEntry] {
        let views = Registry.views.map {
            ReferenceEntry(section: $0.category == .layout ? "Layout views" : "Content views", name: $0.name,
                           summary: $0.summary, example: $0.example, arguments: $0.arguments)
        }
        let modifiers = Registry.modifiers.map {
            ReferenceEntry(section: "Modifiers", name: "." + $0.name, summary: $0.summary,
                           example: $0.example, arguments: $0.arguments)
        }
        return views + modifiers
    }

    /// Entries grouped by section, in registry order.
    public static var sections: [(title: String, entries: [ReferenceEntry])] {
        var order: [String] = []
        var grouped: [String: [ReferenceEntry]] = [:]
        for e in entries {
            if grouped[e.section] == nil { order.append(e.section) }
            grouped[e.section, default: []].append(e)
        }
        return order.map { ($0, grouped[$0]!) }
    }
}
