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
    private static func title(for category: ViewSpec.Category) -> String {
        switch category {
        case .layout: "Layout views"
        case .content: "Content views"
        case .gradient: "Gradients"
        }
    }

    public static var entries: [ReferenceEntry] {
        let views = Registry.views.map {
            ReferenceEntry(section: Self.title(for: $0.category), name: $0.name,
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
