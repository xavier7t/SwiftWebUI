import Foundation

/// The in-app reference of supported views and modifiers. It is generated from `Registry`, so it can't drift.
public struct ReferenceEntry: Equatable, Sendable, Identifiable {
    public var id: String { section + "/" + name }
    public let section: String
    public let name: String
    public let summary: String
    public let example: String
    public let arguments: [ArgumentSpec]
    /// Working code to insert into a file: a view for views, a chained call (starting with a dot) for modifiers.
    public let snippet: String
}

public enum Reference {
    /// Insertable code for views whose one-line example is only a sketch. Everything else inserts its example.
    /// A test checks that every snippet parses and renders without problems.
    static let snippets: [String: String] = [
        "VStack": "VStack(spacing: 8) {\n    Text(\"First\")\n    Text(\"Second\")\n}",
        "HStack": "HStack(spacing: 8) {\n    Text(\"Left\")\n    Spacer()\n    Text(\"Right\")\n}",
        "ZStack": "ZStack {\n    Text(\"Back\")\n    Text(\"Front\")\n}",
        "List": "List {\n    Text(\"One\")\n    Text(\"Two\")\n    Text(\"Three\")\n}",
        "ScrollView": "ScrollView(.horizontal) {\n    HStack(spacing: 16) {\n        Text(\"One\")\n        Text(\"Two\")\n        Text(\"Three\")\n    }\n}",
        "ForEach": "ForEach([\"One\", \"Two\", \"Three\"], id: \\.self) { name in\n    Text(name)\n}",
        "Image": "Image(systemName: \"star.fill\")",
        "Button": "Button(\"Tap me\") { }",
        "LinearGradient": "LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom)\n    .frame(height: 120)",
        "RadialGradient": "RadialGradient(colors: [.yellow, .red], center: .center, startRadius: 0, endRadius: 120)\n    .frame(height: 120)",
        "AngularGradient": "AngularGradient(colors: [.red, .blue, .red], center: .center)\n    .frame(height: 120)",
        "EllipticalGradient": "EllipticalGradient(colors: [.white, .blue])\n    .frame(height: 120)",
        "MeshGradient": "MeshGradient(\n    width: 2, height: 2,\n    points: [[0, 0], [1, 0], [0, 1], [1, 1]],\n    colors: [.red, .blue, .green, .yellow]\n)\n    .frame(height: 120)",
    ]

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
                           summary: $0.summary, example: $0.example, arguments: $0.arguments,
                           snippet: snippets[$0.name] ?? $0.example)
        }
        let modifiers = Registry.modifiers.map {
            ReferenceEntry(section: "Modifiers", name: "." + $0.name, summary: $0.summary,
                           example: $0.example, arguments: $0.arguments, snippet: snippets[$0.name] ?? $0.example)
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
