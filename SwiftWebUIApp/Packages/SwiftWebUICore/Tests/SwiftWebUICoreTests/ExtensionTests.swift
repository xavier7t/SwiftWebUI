import Foundation
import Testing
@testable import SwiftWebUICore

private struct Out { let html: String; let errors: [Diagnostic]; let warnings: [Diagnostic]; let tree: ParseResult }

private func run(_ files: [String: String]) -> Out {
    let sources = files.keys.sorted().map { SourceFile(path: $0, text: files[$0]!) }
    let r = ViewTreeBuilder.build(files: sources, entryView: "ContentView")
    var html = "", warnings = r.diagnostics.filter { $0.severity == .warning }
    if let tree = r.tree {
        let out = HTMLRenderer.render(tree)
        html = out.html
        warnings += out.diagnostics
    }
    return Out(html: html, errors: r.diagnostics.filter { $0.severity == .error }, warnings: warnings, tree: r)
}

private func one(_ source: String) -> Out { run(["ContentView.swift": source]) }

@Suite struct ComputedPropertyTests {
    @Test func viewValuedComputedProperty() {
        let o = one("""
        struct ContentView: View {
            var header: some View {
                VStack { Text("Title"); Text("Sub") }
            }
            var body: some View {
                VStack { header.padding(8); self.header }
            }
        }
        """)
        #expect(o.errors.isEmpty && o.warnings.isEmpty, "\(o.errors) \(o.warnings)")
        #expect(o.html.components(separatedBy: "Title").count == 3) // used twice
        #expect(o.html.contains("padding"))
    }

    @Test func viewBuilderAttributeIsAccepted() {
        let o = one("""
        struct ContentView: View {
            @ViewBuilder var footer: some View { Text("Foot"); Text("Note") }
            var body: some View { VStack { footer } }
        }
        """)
        #expect(o.errors.isEmpty, "\(o.errors)")
        #expect(o.html.contains("Foot") && o.html.contains("Note"))
    }

    @Test func valueComputedProperties() {
        let o = one("""
        struct ContentView: View {
            @State private var count = 2
            let name = "World"
            var greeting: String { "Hello, \\(name)" }
            var counter: String { return "Count: \\(count)" }
            var accent: Color { .purple }
            var body: some View {
                VStack {
                    Text(greeting).foregroundColor(accent)
                    Text(counter)
                    Button("Add") { count += 1 }
                }
            }
        }
        """)
        #expect(o.errors.isEmpty && o.warnings.isEmpty, "\(o.errors) \(o.warnings)")
        #expect(o.html.contains("Hello, World"))
        #expect(o.html.contains("var(--c-purple)"))
        #expect(o.html.contains("data-t"), "state text must stay reactive")
    }

    @Test func computedPropertyCanUseAnother() {
        let o = one("""
        struct ContentView: View {
            var first: String { "A" }
            var second: String { "\\(first)B" }
            var body: some View { Text(second) }
        }
        """)
        #expect(o.errors.isEmpty && o.html.contains("AB"), "\(o.errors) \(o.html)")
    }

    @Test func cyclesAreReportedNotCrashed() {
        let a = one("""
        struct ContentView: View {
            var a: String { b }
            var b: String { a }
            var body: some View { Text(a) }
        }
        """)
        #expect(a.errors.contains { $0.code == .circularReference }, "\(a.errors)")
        let v = one("""
        struct ContentView: View {
            var inner: some View { VStack { inner } }
            var body: some View { inner }
        }
        """)
        #expect(v.errors.contains { $0.code == .circularReference }, "\(v.errors)")
    }

    @Test func multiStatementValueIsAnError() {
        let o = one("""
        struct ContentView: View {
            var title: String { let x = "a"; return x }
            var body: some View { Text(title) }
        }
        """)
        #expect(o.errors.contains { $0.message.contains("single expression") }, "\(o.errors)")
    }
}

@Suite struct ExtensionSupportTests {
    @Test func staticColorAndGradientConstants() {
        let o = one("""
        extension Color {
            static let brand = Color(red: 0.1, green: 0.2, blue: 0.9)
            static var soft: Color { Color.brand.opacity(0.2) }
        }
        extension LinearGradient {
            static let sunset = LinearGradient(colors: [.orange, .pink], startPoint: .top, endPoint: .bottom)
        }
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("a").foregroundColor(.brand)
                    Text("b").background(Color.soft)
                    Text("c").background(.sunset)
                    Color.brand.frame(height: 10)
                    LinearGradient.sunset.frame(height: 10)
                }
            }
        }
        """)
        #expect(o.errors.isEmpty && o.warnings.isEmpty, "\(o.errors) \(o.warnings)")
        #expect(o.html.contains("rgb(26 51 230)"), "\(o.html)")
        #expect(o.html.contains("var(--c-pink)") && o.html.contains("linear-gradient("))
        #expect(o.html.contains("class=\"gradient\"") && o.html.contains("class=\"color\""))
    }

    @Test func extensionsInAnotherFileAndBeforeTheType() {
        let o = run([
            "A.swift": "struct ContentView: View { var body: some View { Text(label).foregroundColor(.brand) } }",
            "B.swift": """
            extension ContentView { var label: String { "From extension" } }
            extension Color { static let brand = Color.red }
            """,
        ])
        #expect(o.errors.isEmpty, "\(o.errors)")
        #expect(o.html.contains("From extension") && o.html.contains("var(--c-red)"))
    }

    @Test func viewExtensionAddsViewComputedProperty() {
        let o = one("""
        extension ContentView { var banner: some View { Text("Banner") } }
        struct ContentView: View { var body: some View { VStack { banner } } }
        """)
        #expect(o.errors.isEmpty && o.html.contains("Banner"), "\(o.errors)")
    }

    @Test func customModifiers() {
        let o = one("""
        extension View {
            func card() -> some View {
                self.padding(16).background(Color.gray).cornerRadius(12)
            }
            func tinted(_ color: Color = .blue, radius: Double = 4) -> some View {
                background(color).cornerRadius(radius)
            }
            func loud() -> some View { self.font(.title).card() }
        }
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("A").card()
                    Text("B").tinted()
                    Text("C").tinted(.red, radius: 10)
                    Text("D").loud()
                }
            }
        }
        """)
        #expect(o.errors.isEmpty && o.warnings.isEmpty, "\(o.errors) \(o.warnings)")
        #expect(o.html.contains("border-radius:12px") && o.html.contains("var(--c-gray)"))
        #expect(o.html.contains("var(--c-blue)") && o.html.contains("border-radius:4px"))
        #expect(o.html.contains("var(--c-red)") && o.html.contains("border-radius:10px"))
        #expect(o.html.contains("font-size:28px"))
    }

    @Test func customModifierOrderMatchesInlineModifiers() {
        let a = one("""
        extension View { func boxed() -> some View { self.padding(10).background(Color.red) } }
        struct ContentView: View { var body: some View { Text("x").boxed() } }
        """)
        let b = one("struct ContentView: View { var body: some View { Text(\"x\").padding(10).background(Color.red) } }")
        #expect(a.errors.isEmpty)
        #expect(a.html == b.html, "\(a.html)\n\(b.html)")
    }

    @Test func customModifierProblems() {
        let o = one("""
        extension View {
            func card(color: Color) -> some View { self.background(color) }
            func loop() -> some View { self.loop() }
            func other() -> some View { VStack { self } }
        }
        struct ContentView: View {
            var body: some View {
                VStack {
                    Text("a").card()
                    Text("b").card(colour: .red)
                    Text("c").loop()
                    Text("d").other()
                    Text("e").nope()
                }
            }
        }
        """)
        let codes = Set(o.errors.map(\.code))
        #expect(o.errors.contains { $0.message.contains("Unknown modifier “VStack”") }) // only modifiers can be chained on self
        #expect(codes.isSuperset(of: [.missingArgument, .unknownArgument, .circularReference, .unknownModifier]), "\(o.errors)")
    }

    @Test func unsupportedExtensionMembersWarn() {
        let o = one("""
        extension ContentView { func helper() {} }
        struct ContentView: View { var body: some View { Text("x") } }
        """)
        #expect(o.errors.isEmpty)
        #expect(o.warnings.contains { $0.message.contains("ignored") }, "\(o.warnings)")
    }

    @Test func everyPrefixOfExtensionCodeParsesWithoutCrashing() {
        let source = """
        extension Color { static let brand = Color.blue }
        extension View { func card(_ c: Color = .brand) -> some View { self.padding().background(c) } }
        struct ContentView: View {
            var title: String { "Hi" }
            var header: some View { Text(title).card() }
            var body: some View { header }
        }
        """
        var prefix = ""
        for ch in source {
            prefix.append(ch)
            _ = ViewTreeBuilder.build(source: prefix, entryView: "ContentView")
        }
    }
}
