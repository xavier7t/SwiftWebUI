import Testing
@testable import SwiftWebUICore

@Suite struct UserExampleTests {
    @Test func colorComputedPropertyInExtension() {
        let source = """
        import SwiftUI

        struct ContentView: View {
            @State private var num: Int = 0
            var body: some View {
                pageBackgroundColor
            }
        }

        // Computed Properties
        extension ContentView {
            var pageBackgroundColor: Color {
                Color(
                    red: 0.6,
                    green: 0.8,
                    blue: 0.6
                )
            }
        }
        """
        let r = ViewTreeBuilder.build(source: source, entryView: "ContentView")
        #expect(r.diagnostics.isEmpty, "\(r.diagnostics)")
        if let tree = r.tree {
            let out = HTMLRenderer.render(tree)
            #expect(out.diagnostics.isEmpty, "\(out.diagnostics)")
            #expect(out.html.contains("background-color:rgb(153 204 153)"), "\(out.html)")
        }
    }
}

@Suite struct ShapeStyleComputedTests {
    private func run(_ body: String, extra: String) -> (html: String, errors: [Diagnostic], warnings: [Diagnostic]) {
        let src = "struct ContentView: View {\n var body: some View { \(body) }\n}\nextension ContentView {\n\(extra)\n}"
        let r = ViewTreeBuilder.build(source: src, entryView: "ContentView")
        var html = "", w: [Diagnostic] = []
        if let t = r.tree { let o = HTMLRenderer.render(t); html = o.html; w = o.diagnostics }
        return (html, r.diagnostics.filter { $0.severity == .error }, w)
    }

    @Test func implicitMemberColor() {
        let r = run("bg", extra: "var bg: Color { .blue }")
        #expect(r.errors.isEmpty && r.warnings.isEmpty && r.html.contains("var(--c-blue)"), "\(r.errors) \(r.html)")
    }

    @Test func usedAsViewValueAndWithModifiers() {
        let r = run("ZStack { bg.frame(width: 40, height: 40); Text(\"x\").background(bg) }", extra: "var bg: Color { Color.red.opacity(0.5) }")
        #expect(r.errors.isEmpty && r.warnings.isEmpty, "\(r.errors) \(r.warnings)")
        #expect(r.html.components(separatedBy: "var(--c-red) 50%").count == 3, "\(r.html)")
    }

    @Test func gradientComputedProperty() {
        let r = run("self.sky", extra: "var sky: LinearGradient { LinearGradient(colors: [.blue, .purple], startPoint: .top, endPoint: .bottom) }")
        #expect(r.errors.isEmpty && r.warnings.isEmpty && r.html.contains("linear-gradient(180deg"), "\(r.errors) \(r.html)")
    }
}
