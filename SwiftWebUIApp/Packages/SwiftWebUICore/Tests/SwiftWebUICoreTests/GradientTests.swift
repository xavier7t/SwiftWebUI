import Foundation
import Testing
@testable import SwiftWebUICore

private func render(_ body: String) -> (html: String, diagnostics: [Diagnostic], parse: [Diagnostic]) {
    let r = ViewTreeBuilder.build(source: "struct ContentView: View { var body: some View { \(body) } }", entryView: "ContentView")
    guard let tree = r.tree else { return ("", [], r.diagnostics) }
    let out = HTMLRenderer.render(tree)
    return (out.html, out.diagnostics, r.diagnostics.filter { $0.severity == .error })
}

private func css(_ gradient: String, as usage: String = "Text(\"x\").background(%@)") -> String {
    let r = render(usage.replacingOccurrences(of: "%@", with: gradient))
    #expect(r.parse.isEmpty, "\(r.parse)")
    #expect(r.diagnostics.isEmpty, "\(r.diagnostics)")
    return r.html
}

@Suite struct GradientTests {
    @Test func linearVertical() {
        let html = css("LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)")
        #expect(html.contains("linear-gradient(180deg, var(--c-red) 0%, var(--c-blue) 100%)"), "\(html)")
    }

    @Test func linearDiagonalUsesCorners() {
        let html = css("LinearGradient(colors: [.red, .blue], startPoint: .topLeading, endPoint: .bottomTrailing)")
        #expect(html.contains("linear-gradient(to bottom right, var(--c-red) 0%, var(--c-blue) 100%)"), "\(html)")
    }

    @Test func linearWithStopsAndGradientArgument() {
        let a = css("LinearGradient(stops: [Gradient.Stop(color: .red, location: 0.2), Gradient.Stop(color: .blue, location: 0.8)], startPoint: .leading, endPoint: .trailing)")
        #expect(a.contains("var(--c-red) 20%, var(--c-blue) 80%"), "\(a)")
        let b = css("LinearGradient(gradient: Gradient(colors: [.red, .green, .blue]), startPoint: .leading, endPoint: .trailing)")
        #expect(b.contains("var(--c-green) 50%"), "\(b)")
    }

    @Test func linearPartialRangeRemapsStops() {
        // From the top to the middle: the last color is reached at 50% of the box.
        let html = css("LinearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .center)")
        #expect(html.contains("var(--c-blue) 50%"), "\(html)")
    }

    @Test func radial() {
        let html = css("RadialGradient(colors: [.yellow, .red], center: .center, startRadius: 10, endRadius: 110)")
        #expect(html.contains("radial-gradient(circle farthest-corner at 50% 50%, var(--c-yellow) 10px, var(--c-red) 110px)"), "\(html)")
    }

    @Test func elliptical() {
        let html = css("EllipticalGradient(colors: [.white, .blue])")
        #expect(html.contains("radial-gradient(ellipse 50% 50% at 50% 50%, #FFFFFF 0%, var(--c-blue) 100%)"), "\(html)")
        let custom = css("EllipticalGradient(colors: [.white, .blue], center: .topLeading, startRadiusFraction: 0.1, endRadiusFraction: 0.5)")
        #expect(custom.contains("at 0% 0%") && custom.contains("20%"), "\(custom)")
    }

    @Test func angular() {
        let html = css("AngularGradient(colors: [.red, .blue, .red], center: .center)")
        #expect(html.contains("conic-gradient(from 90deg at 50% 50%, var(--c-red) 0deg, var(--c-blue) 180deg, var(--c-red) 360deg)"), "\(html)")
        let arc = css("AngularGradient(colors: [.red, .blue], center: .center, startAngle: .degrees(0), endAngle: .degrees(180))")
        #expect(arc.contains("var(--c-blue) 180deg"), "\(arc)")
        let rotated = css("AngularGradient(gradient: Gradient(colors: [.red, .blue]), center: .center, angle: .degrees(90))")
        #expect(rotated.contains("from 180deg"), "\(rotated)")
    }

    @Test func mesh() {
        let html = css("""
        MeshGradient(width: 2, height: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], colors: [.red, .blue, .green, .yellow], background: .black)
        """)
        #expect(html.components(separatedBy: "radial-gradient(").count == 5, "\(html)")
        #expect(html.contains("at 100% 100%") && html.contains("linear-gradient(#000000, #000000)"), "\(html)")
    }

    @Test func gradientsWorkAsViews() {
        let r = render("ZStack { LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing); Text(\"Hi\") }")
        #expect(r.parse.isEmpty && r.diagnostics.isEmpty, "\(r.parse) \(r.diagnostics)")
        #expect(r.html.contains("class=\"gradient\""), "\(r.html)")
        #expect(r.html.contains("linear-gradient(90deg"), "\(r.html)")
    }

    @Test func staticMemberSyntax() {
        let html = css(".linearGradient(colors: [.red, .blue], startPoint: .top, endPoint: .bottom)")
        #expect(html.contains("linear-gradient("), "\(html)")
    }

    @Test func foregroundStyleClipsToText() {
        let html = css("LinearGradient(colors: [.pink, .orange], startPoint: .leading, endPoint: .trailing)",
                       as: "Text(\"Hi\").font(.largeTitle).foregroundStyle(%@)")
        #expect(html.contains("background-clip:text") && html.contains("color:transparent"), "\(html)")
    }

    @Test func gradientAsColorUsesUnitPointAndMoreColors() {
        let html = css("LinearGradient(colors: [Color(red: 1, green: 0, blue: 0), .blue.opacity(0.5)], startPoint: UnitPoint(x: 0, y: 0.25), endPoint: UnitPoint(x: 1, y: 0.75))")
        #expect(html.contains("linear-gradient(") && html.contains("rgb(255 0 0)"), "\(html)")
    }

    @Test func problemsAreWarningsNotCrashes() {
        for bad in [
            "LinearGradient(colors: [.red, .nope], startPoint: .top, endPoint: .bottom)",
            "LinearGradient(colors: [.red, .blue], startPoint: .middle, endPoint: .bottom)",
            "RadialGradient(colors: [.red, .blue], center: .center, startRadius: 0, endRadius: 10).self",
            "MeshGradient(width: 3, height: 3, points: [[0, 0]], colors: [.red])",
            "AngularGradient(colors: [.red, .blue], center: .center, angle: 90)",
        ] {
            let r = render("Text(\"x\").background(\(bad))")
            #expect(r.parse.isEmpty || !r.parse.isEmpty) // must not crash
            if r.parse.isEmpty { #expect(!r.diagnostics.isEmpty || bad.hasSuffix(".self"), "\(bad)") }
        }
        let mesh = render("Text(\"x\").background(MeshGradient(width: 3, height: 3, points: [[0, 0]], colors: [.red]))")
        #expect(mesh.diagnostics.first?.message.contains("needs 9 points") == true, "\(mesh.diagnostics)")
    }

    @Test func missingArgumentsAreErrorsWithHints() {
        let r = render("LinearGradient(colors: [.red], startPoint: .top)")
        #expect(r.parse.contains { $0.code == .missingArgument }, "\(r.parse)")
        let u = render("LinearGradient(color: [.red], startPoint: .top, endPoint: .bottom)")
        #expect(u.parse.contains { $0.code == .unknownArgument })
    }

    @Test func referenceListsGradients() {
        let names = Reference.sections.first { $0.title == "Gradients" }?.entries.map(\.name)
        #expect(names == ["LinearGradient", "RadialGradient", "AngularGradient", "EllipticalGradient", "MeshGradient"])
    }
}
