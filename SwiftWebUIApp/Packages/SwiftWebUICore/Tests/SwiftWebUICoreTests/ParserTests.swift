import Foundation
import Testing
@testable import SwiftWebUICore

private func view(_ body: String, extra: String = "") -> String {
    """
    import SwiftUI
    \(extra)
    struct ContentView: View {
        var body: some View {
            \(body)
        }
    }
    """
}

/// Outline of the entry view's content (skipping the ContentView wrapper).
private func outline(_ body: String, extra: String = "") -> String {
    let r = ViewTreeBuilder.build(source: view(body, extra: extra))
    return r.tree?.root.children.map(\.outline).joined(separator: "\n") ?? "<nil> \(r.diagnostics)"
}

private func diagnostics(_ source: String) -> [Diagnostic] { ViewTreeBuilder.build(source: source).diagnostics }

// MARK: - Views

@Suite struct ViewFixtureTests {
    @Test func text() {
        #expect(outline("Text(\"Hello\")") == "Text(\"Hello\")")
    }

    @Test func stacks() {
        #expect(outline("""
        VStack(alignment: .leading, spacing: 8) {
            Text("a")
            HStack { Text("b"); Text("c") }
            ZStack { Text("d") }
        }
        """) == """
        VStack(alignment: .leading, spacing: 8)
          Text("a")
          HStack
            Text("b")
            Text("c")
          ZStack
            Text("d")
        """)
    }

    @Test func spacer() {
        #expect(outline("HStack { Spacer(); Spacer(minLength: 4) }") == """
        HStack
          Spacer
          Spacer(minLength: 4)
        """)
    }

    @Test func imageButtonLink() {
        #expect(outline("Image(\"logo\")") == "Image(\"logo\")")
        #expect(outline("Image(systemName: \"star\")") == "Image(systemName: \"star\")")
        #expect(outline("Link(\"Docs\", destination: \"https://example.com\")")
                == "Link(\"Docs\", destination: \"https://example.com\")")
    }

    @Test func list() {
        #expect(outline("List { Text(\"a\"); Text(\"b\") }") == """
        List
          Text("a")
          Text("b")
        """)
    }

    @Test func forEachRangeAndArray() {
        #expect(outline("VStack { ForEach(0..<3) { i in Text(\"Row \\(i)\") } }") == """
        VStack
          ForEach
            Text("Row 0")
            Text("Row 1")
            Text("Row 2")
        """)
        #expect(outline("ForEach(1...2) { Text(\"n\\($0)\") }") == """
        ForEach
          Text("n1")
          Text("n2")
        """)
        #expect(outline("ForEach([\"A\", \"B\"], id: \\.self) { name in Text(name) }") == """
        ForEach
          Text("A")
          Text("B")
        """)
    }

    @Test func locationsAreRecorded() throws {
        let r = ViewTreeBuilder.build(source: view("Text(\"x\")"))
        let text = try #require(r.tree?.root.children.first)
        #expect(text.location.line == 5)
        #expect(text.location.column == 9)
    }
}

// MARK: - Modifiers

@Suite struct ModifierFixtureTests {
    @Test func allModifiersInOrder() {
        #expect(outline("""
        Text("Hi")
            .padding()
            .padding(.horizontal, 8)
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(.white.opacity(0.8))
            .background(Color.blue)
            .frame(maxWidth: .infinity, minHeight: 44)
            .cornerRadius(8)
        """) == """
        Text("Hi") .padding() .padding(.horizontal, 8) .font(.system(size: 20, weight: .bold)) \
        .foregroundColor(.white.opacity(0.8)) .background(Color.blue) \
        .frame(maxWidth: .infinity, minHeight: 44) .cornerRadius(8)
        """)
    }

    @Test func foregroundStyleAndColorInit() {
        #expect(outline("Text(\"a\").foregroundStyle(Color(red: 0.1, green: 0.2, blue: 0.3))")
                == "Text(\"a\") .foregroundStyle(Color.init(red: 0.1, green: 0.2, blue: 0.3))")
    }

    @Test func modifiersOnStacksAndNegativeNumbers() {
        #expect(outline("VStack { Text(\"a\") }.padding(-4)") == """
        VStack .padding(-4)
          Text("a")
        """)
    }
}

// MARK: - State

@Suite struct StateTests {
    let counter = """
    struct ContentView: View {
        @State private var count = 0
        @State var on = false
        let step = 2
        var body: some View {
            VStack {
                Text("Count: \\(count)")
                Button("Add") { count += step }
                Button("Reset") { count = 0 }
                Button("Sub") { count -= 1 }
                Button("Flip") { on.toggle() }
                Button { on = !on } label: { Text("Flip 2") }
                Button(action: { count += 1 }) { Text("Inc") }
            }
        }
    }
    """

    @Test func statesAndActions() throws {
        let r = ViewTreeBuilder.build(source: counter)
        #expect(r.diagnostics.isEmpty)
        let tree = try #require(r.tree)
        #expect(tree.states.map(\.id) == ["ContentView.count", "ContentView.on"])
        #expect(tree.states.map(\.initial) == [.number(0), .bool(false)])
        #expect(tree.root.children[0].outline == """
        VStack
          Text("Count: \\($ContentView.count)")
          Button("Add") {$ContentView.count += 2}
          Button("Reset") {$ContentView.count = 0}
          Button("Sub") {$ContentView.count += -1}
          Button("Flip") {$ContentView.on.toggle()}
          Button {$ContentView.on.toggle()}
            Text("Flip 2")
          Button {$ContentView.count += 1}
            Text("Inc")
        """)
    }

    @Test func eachInstanceGetsItsOwnState() throws {
        let src = """
        struct Counter: View {
            @State var n = 0
            var body: some View { Button("+") { n += 1 } }
        }
        struct ContentView: View {
            var body: some View { VStack { Counter(); Counter() } }
        }
        """
        let r = ViewTreeBuilder.build(source: src, entryView: "ContentView")
        #expect(r.diagnostics.isEmpty)
        #expect(r.tree?.states.map(\.id) == ["Counter.n", "Counter#2.n"])
    }

    @Test func nonStateTargetIsAnError() {
        let d = diagnostics("""
        struct ContentView: View {
            let n = 1
            var body: some View { Button("x") { n += 1 } }
        }
        """)
        #expect(d.contains { $0.code == .invalidState && $0.message.contains("“n” isn’t a @State variable") })
    }
}

// MARK: - Custom views and multiple files

@Suite struct CompositionTests {
    @Test func storedPropertiesAndArguments() throws {
        let src = """
        struct Card: View {
            let title: String
            var subtitle = "default"
            let fixed = "f"
            var body: some View {
                VStack { Text(title); Text(subtitle); Text(fixed) }
            }
        }
        struct ContentView: View {
            var body: some View { Card(title: "T"); Card(title: "U", subtitle: "S") }
        }
        """
        let r = ViewTreeBuilder.build(source: src, entryView: "ContentView")
        #expect(r.diagnostics.isEmpty)
        let group = try #require(r.tree?.root.children.first)
        #expect(group.kind == "Group")
        #expect(group.children.map(\.kind) == ["Card", "Card"])
        let cards = try #require(r.tree?.root.children.first?.children)
        #expect(cards[0].children[0].outline == """
        VStack
          Text("T")
          Text("default")
          Text("f")
        """)
        #expect(cards[1].children[0].children.map(\.outline) == ["Text(\"U\")", "Text(\"S\")", "Text(\"f\")"])
    }

    @Test func resolvesAcrossFiles() throws {
        let files = [
            SourceFile(path: "ContentView.swift", text: "struct ContentView: View { var body: some View { Header().padding() } }"),
            SourceFile(path: "Parts/Header.swift", text: "struct Header: View { var body: some View { Text(\"Hi\") } }"),
        ]
        let r = ViewTreeBuilder.build(files: files)
        #expect(r.diagnostics.isEmpty)
        #expect(r.tree?.root.outline == """
        ContentView [custom]
          Header [custom] .padding()
            Text("Hi")
        """)
    }

    @Test func circularReferencesAreReported() {
        let files = [
            SourceFile(path: "A.swift", text: "struct ContentView: View { var body: some View { B() } }"),
            SourceFile(path: "B.swift", text: "struct B: View { var body: some View { ContentView() } }"),
        ]
        let r = ViewTreeBuilder.build(files: files)
        let d = r.diagnostics.first { $0.code == .circularReference }
        #expect(d?.message == "“ContentView” contains itself (ContentView → B → ContentView).")
        #expect(d?.location.file == "B.swift")
        #expect(r.tree != nil)
    }

    @Test func selfReferenceIsReported() {
        let d = diagnostics("struct ContentView: View { var body: some View { VStack { ContentView() } } }")
        #expect(d.contains { $0.code == .circularReference })
    }

    @Test func missingEntryView() {
        let r = ViewTreeBuilder.build(files: [SourceFile(path: "A.swift", text: "struct Home: View { var body: some View { Text(\"x\") } }")],
                                      entryView: "Hom")
        #expect(r.tree == nil)
        #expect(r.diagnostics.first?.code == .missingEntryView)
        #expect(r.diagnostics.first?.suggestion == "Did you mean “Home”?")
    }

    @Test func unusedViewsAreStillChecked() {
        let files = [
            SourceFile(path: "ContentView.swift", text: "struct ContentView: View { var body: some View { Text(\"x\") } }"),
            SourceFile(path: "Other.swift", text: "struct Other: View { var body: some View { Textt(\"x\") } }"),
        ]
        let r = ViewTreeBuilder.build(files: files)
        #expect(r.diagnostics.contains { $0.code == .unknownView && $0.location.file == "Other.swift" })
        #expect(r.tree?.states.isEmpty == true)
    }

    @Test func parsesAProjectOnDisk() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("parser-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir.createDir())
        let result = ProjectParser.parse(project: project)
        #expect(result.diagnostics.isEmpty)
        #expect(result.tree?.root.kind == "ContentView")
        #expect(result.tree?.root.children.first?.kind == "VStack")
    }
}

private extension URL {
    func createDir() throws -> URL {
        try FileManager.default.createDirectory(at: self, withIntermediateDirectories: true)
        return self
    }
}

// MARK: - Errors

@Suite struct DiagnosticTests {
    private func first(_ body: String, extra: String = "") -> Diagnostic? {
        ViewTreeBuilder.build(source: view(body, extra: extra)).diagnostics.first
    }

    @Test func unknownView() {
        let d = first("Textt(\"x\")")
        #expect(d?.code == .unknownView)
        #expect(d?.message == "Unknown view “Textt”.")
        #expect(d?.suggestion == "Did you mean “Text”?")
        #expect(d?.location.line == 5 && d?.location.column == 9)
    }

    @Test func unknownViewWithoutCloseMatch() {
        #expect(first("Carousel()")?.suggestion?.contains("define “struct Carousel: View”") == true)
    }

    @Test func unknownModifier() {
        let d = first("Text(\"x\").bold()")
        #expect(d?.code == .unknownModifier)
        #expect(d?.message == "Unknown modifier “bold”.")
        #expect(d?.suggestion?.contains("Supported modifiers") == true)
        #expect(first("Text(\"x\").paddin()")?.suggestion == "Did you mean “padding”?")
    }

    @Test func unknownAndMissingArguments() {
        #expect(first("VStack(spacin: 4) { }")?.suggestion == "Did you mean “spacing”?")
        #expect(first("VStack(spacin: 4) { }")?.code == .unknownArgument)
        #expect(first("Text()")?.code == .missingArgument)
        #expect(first("Text(\"x\").font()")?.code == .missingArgument)
        #expect(first("Text(\"a\", \"b\")")?.code == .invalidArgument)
        #expect(first("Link(\"a\")")?.code == .missingArgument)
        #expect(first("List { }.frame()")?.code == .missingArgument)
    }

    @Test func unsupportedSyntax() {
        #expect(first("if true { Text(\"a\") }")?.message == "“if” and “switch” aren’t supported in views yet.")
        #expect(first("Text(\"a\").background { Text(\"b\") }")?.code == .unsupportedSyntax)
        #expect(first("let x = 1\nText(\"a\")")?.message == "Local declarations aren’t supported in a view body.")
        #expect(first("Text(\"a\" + \"b\")")?.code == .unsupportedSyntax)
        #expect(first("ForEach(items) { Text($0) }", extra: "let items = [1]")?.code == .unknownName)
        #expect(first("Spacer { }")?.code == .unsupportedSyntax)
        #expect(first("List()")?.code == .missingArgument)
    }

    @Test func unknownNameSuggestsCloseMatch() {
        let d = ViewTreeBuilder.build(source: """
        struct ContentView: View {
            let title = "x"
            var body: some View { Text(titl) }
        }
        """).diagnostics.first
        #expect(d?.code == .unknownName)
        #expect(d?.suggestion == "Did you mean “title”?")
    }

    @Test func unsupportedPropertyWrappersAndMembers() {
        let d = diagnostics("""
        struct ContentView: View {
            @Binding var x: Bool
            var computed: Int { 1 }
            func f() {}
            @State var missing: Int
            var body: some View { Text("a") }
        }
        """)
        #expect(d.contains { $0.message == "@Binding isn’t supported yet." })
        #expect(!d.contains { $0.message.contains("Computed property") }) // computed properties are supported now
        #expect(d.contains { $0.severity == .warning && $0.code == .unsupportedSyntax })
        #expect(d.contains { $0.code == .invalidState })
    }

    @Test func customViewArgumentErrors() {
        let extra = "struct Card: View { let title: String; var body: some View { Text(title) } }"
        func all(_ body: String) -> [Diagnostic] { ViewTreeBuilder.build(source: view(body, extra: extra)).diagnostics }
        #expect(all("Card()").map(\.code) == [.missingArgument])
        #expect(all("Card(titel: \"x\")").contains { $0.code == .unknownArgument && $0.suggestion == "Did you mean “title”?" })
        #expect(all("Card(\"x\")").contains { $0.code == .invalidArgument })
    }

    @Test func syntaxErrorsAreReportedWithLocation() {
        let d = diagnostics("struct ContentView: View {\n    var body: some View {\n        Text(\"x\"\n    }\n}\n")
        #expect(d.contains { $0.code == .syntaxError && $0.location.line >= 3 })
    }

    @Test func validPartsSurviveErrors() throws {
        let r = ViewTreeBuilder.build(source: view("""
        VStack {
            Text("ok")
            Bogus()
            Text("also ok").bold().padding()
        }
        """))
        #expect(r.diagnostics.count == 2)
        #expect(r.tree?.root.children[0].outline == """
        VStack
          Text("ok")
          Text("also ok") .padding()
        """)
    }

    @Test func columnsCountCharactersNotBytes() {
        let d = ViewTreeBuilder.build(source: view("Text(\"é🌍\"); Bogus()")).diagnostics.first
        #expect(d?.location.column == 9 + "Text(\"é🌍\"); ".count)
    }
}

// MARK: - Robustness and performance

private let fixtures: [String] = [
    Project.defaultEntrySource,
    """
    struct Card: View {
        let title: String
        var body: some View {
            VStack(alignment: .leading, spacing: 4) { Text(title).font(.headline) }
                .padding().background(Color.gray).cornerRadius(8)
        }
    }
    struct ContentView: View {
        @State var count = 0
        var body: some View {
            List { ForEach(0..<3) { i in Card(title: "Row \\(i)") }
            Button("Add") { count += 1 }
            Link("x", destination: "https://e.com") }
        }
    }
    """,
]

@Suite struct RobustnessTests {
    @Test func everyPrefixOfFixturesParsesWithoutCrashing() {
        for fixture in fixtures {
            var prefix = ""
            for ch in fixture {
                prefix.append(ch)
                _ = ViewTreeBuilder.build(source: prefix, entryView: "ContentView")
            }
        }
    }

    @Test func largeProjectParsesQuickly() {
        var source = ""
        for i in 0..<40 {
            source += """
            struct Section\(i): View {
                @State var n = 0
                var body: some View {
                    VStack(spacing: 8) {
                        Text("Title \(i)").font(.title).padding()
                        HStack { Text("a"); Spacer(); Text("b") }
                        Button("Add") { n += 1 }
                        ForEach(0..<2) { j in Text("Item \\(j)").foregroundColor(.blue) }
                    }
                    .padding().background(Color.gray).cornerRadius(8)
                }
            }

            """
        }
        source += "struct ContentView: View { var body: some View { VStack {\n"
        for i in 0..<40 { source += "Section\(i)()\n" }
        source += "} } }\n"
        let lineCount = source.split(separator: "\n").count
        #expect(lineCount >= 500)
        let files = [SourceFile(path: "ContentView.swift", text: source)]
        _ = ViewTreeBuilder.build(files: files) // warm up
        let clock = ContinuousClock()
        let elapsed = clock.measure { _ = ViewTreeBuilder.build(files: files) }
        let ms = Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000
        print("parse of \(lineCount) lines: \(ms) ms")
        #expect(ViewTreeBuilder.build(files: files).errors.isEmpty)
        #expect(ms < 50 * Self.slack)
    }

    /// Debug builds of SwiftSyntax are several times slower; the 50 ms budget applies to release.
    static var slack: Double {
        #if DEBUG
        return 10
        #else
        return 1
        #endif
    }
}

@Suite struct RegistryTests {
    @Test func registryNamesAreUniqueAndComplete() {
        #expect(Set(Registry.views.map(\.name)).count == Registry.views.count)
        #expect(Set(Registry.modifiers.map(\.name)).count == Registry.modifiers.count)
        for name in ["VStack", "HStack", "ZStack", "Spacer", "List", "ForEach", "Text", "Image", "Button", "Link"] {
            #expect(Registry.view(named: name) != nil)
        }
        for name in ["padding", "font", "foregroundColor", "background", "frame", "cornerRadius"] {
            #expect(Registry.modifier(named: name) != nil)
        }
    }
}
