import Foundation
import Testing
@testable import SwiftWebUICore

private func render(_ body: String, extra: String = "", state: String = "") -> RenderOutput {
    let source = """
    import SwiftUI
    struct ContentView: View {
        \(state)
        var body: some View {
            \(body)
        }
    }
    \(extra)
    """
    let result = ViewTreeBuilder.build(source: source)
    precondition(!result.hasErrors, "fixture has errors: \(result.diagnostics)")
    return HTMLRenderer.render(result.tree!)
}

private func html(_ body: String, extra: String = "", state: String = "") -> String {
    render(body, extra: extra, state: state).html
}

// MARK: - Views

@Suite struct ViewSnapshotTests {
    @Test func text() {
        #expect(html("Text(\"Hi <b> & you\")") == #"<div class="text">Hi &lt;b&gt; &amp; you</div>"#)
    }

    @Test func vstack() {
        #expect(html("VStack(alignment: .leading, spacing: 4) { Text(\"a\"); Text(\"b\") }")
            == #"<div class="vstack" style="display:flex;flex-direction:column;align-items:flex-start;justify-content:center;gap:4px"><div class="text">a</div><div class="text">b</div></div>"#)
    }

    @Test func hstackDefaults() {
        #expect(html("HStack { Text(\"a\") }")
            == #"<div class="hstack" style="display:flex;flex-direction:row;align-items:center;justify-content:center;gap:8px"><div class="text">a</div></div>"#)
        #expect(html("HStack(alignment: .top) { Text(\"a\") }").contains("align-items:flex-start"))
    }

    @Test func zstackUsesGrid() {
        #expect(html("ZStack(alignment: .topLeading) { Text(\"a\"); Text(\"b\") }")
            == #"<div class="zstack" style="display:grid;justify-items:start;align-items:start"><div class="text" style="grid-area:1/1">a</div><div class="text" style="grid-area:1/1">b</div></div>"#)
    }

    @Test func spacerFillsAlongTheStack() {
        let row = html("HStack { Text(\"a\"); Spacer(); Text(\"b\") }")
        #expect(row.contains(#"<div class="spacer" style="flex:1 1 0"></div>"#))
        #expect(row.contains("gap:8px;flex-grow:1")) // a row with a spacer fills the width it is offered
        // A spacer in a row doesn't make the row grow vertically.
        let nested = html("VStack { HStack { Spacer() } }")
        #expect(nested.contains(#"class="hstack" style="display:flex;flex-direction:row;align-items:center;justify-content:center;gap:8px;align-self:stretch""#))
        #expect(!nested.contains("height")) // and doesn't claim extra height
    }

    @Test func spacerMinLength() {
        #expect(html("VStack { Spacer(minLength: 20) }").contains("min-width:20px;min-height:20px"))
    }

    @Test func listWrapsRowsAndFlattensForEach() {
        let out = html("List { Text(\"a\"); ForEach([\"x\", \"y\"], id: \\.self) { s in Text(s) } }")
        #expect(out.hasPrefix(#"<div class="list" role="list""#))
        #expect(out.components(separatedBy: #"<div class="row" role="listitem">"#).count == 4)
    }

    @Test func forEachRepeatsContent() {
        let out = html("VStack { ForEach(1...3) { i in Text(\"n\\(i)\") } }")
        #expect(out.contains(">n1</div><div class=\"text\">n2</div><div class=\"text\">n3</div>"))
    }

    @Test func imageAssetAndSymbol() {
        #expect(html("Image(\"logo\")") == #"<img class="image" src="logo" alt="logo">"#)
        let resolved = HTMLRenderer.render(
            ViewTreeBuilder.build(source: "struct ContentView: View { var body: some View { Image(\"logo\") } }").tree!,
            options: RenderOptions(assetResolver: { "data:image/png;base64,AAA" + $0 }))
        #expect(resolved.html == #"<img class="image" src="data:image/png;base64,AAAlogo" alt="logo">"#)
        #expect(html("Image(systemName: \"star.fill\")") == #"<span class="sym" role="img" aria-label="star.fill">★</span>"#)
        #expect(html("Image(\"https://example.com/a.png\")").contains(#"src="https://example.com/a.png""#))
    }

    @Test func button() {
        #expect(html("Button(\"Add\") { count += 1 }", state: "@State var count = 0")
            == #"<button class="button" type="button" data-a="[[&quot;add&quot;,&quot;ContentView.count&quot;,1]]">Add</button>"#)
        #expect(html("Button(\"Go\") { on.toggle(); name = \"x\" }", state: "@State var on = false\n@State var name = \"\"")
            .contains("[[&quot;toggle&quot;,&quot;ContentView.on&quot;],[&quot;set&quot;,&quot;ContentView.name&quot;,&quot;x&quot;]]"))
    }

    @Test func buttonWithLabelView() {
        let out = html("Button(action: { count += 1 }) { Text(\"Plus\") }", state: "@State var count = 0")
        #expect(out.contains("<button class=\"button\"") && out.contains("<div class=\"text\">Plus</div></button>"))
    }

    @Test func link() {
        #expect(html("Link(\"Docs\", destination: \"https://example.com/a?b=1&c=2\")")
            == #"<a class="link" href="https://example.com/a?b=1&amp;c=2">Docs</a>"#)
    }

    @Test func unsafeLinkIsNotEmitted() {
        let out = render("Link(\"Bad\", destination: \"javascript:alert(1)\")")
        #expect(out.html == ##"<a class="link" href="#">Bad</a>"##)
        #expect(out.diagnostics.first?.severity == .warning)
    }

    @Test func customViewsAreInlined() {
        let out = html("VStack { Card(title: \"T\") }", extra: """
        struct Card: View { let title: String
            var body: some View { Text(title).font(.headline) } }
        """)
        #expect(out.contains(#"<div class="text" style="font-size:17px;font-weight:600">T</div>"#))
    }

    @Test func rootWithSeveralViewsStacksThem() {
        let out = html("Text(\"a\"); Text(\"b\")")
        #expect(out.hasPrefix(#"<div class="vstack""#))
    }
}

// MARK: - Modifiers

@Suite struct ModifierSnapshotTests {
    @Test func padding() {
        #expect(html("Text(\"a\").padding()").contains(#"style="padding:16px""#))
        #expect(html("Text(\"a\").padding(8)").contains(#"style="padding:8px""#))
        #expect(html("Text(\"a\").padding(.horizontal)").contains(#"style="padding-right:16px;padding-left:16px""#))
        #expect(html("Text(\"a\").padding(.top, 4)").contains(#"style="padding-top:4px""#))
        #expect(html("Text(\"a\").padding([.top, .leading], 2)").contains(#"style="padding-top:2px;padding-left:2px""#))
    }

    @Test func font() {
        #expect(html("Text(\"a\").font(.largeTitle)").contains("font-size:34px;font-weight:400"))
        #expect(html("Text(\"a\").font(.title.bold())").contains("font-size:28px;font-weight:700"))
        #expect(html("Text(\"a\").font(.system(size: 20, weight: .semibold, design: .rounded))")
            .contains("font-size:20px;font-weight:600;font-family:ui-rounded"))
        #expect(html("Text(\"a\").font(.body.italic())").contains("font-style:italic"))
    }

    @Test func colors() {
        #expect(html("Text(\"a\").foregroundColor(.red)").contains("color:var(--c-red)"))
        #expect(html("Text(\"a\").foregroundStyle(Color.blue)").contains("color:var(--c-blue)"))
        #expect(html("Text(\"a\").foregroundColor(.white.opacity(0.5))").contains("color:color-mix(in srgb, #FFFFFF 50%, transparent)"))
        #expect(html("Text(\"a\").background(Color(red: 1, green: 0.5, blue: 0))").contains("background-color:rgb(255 128 0)"))
        #expect(html("Text(\"a\").background(Color(white: 0.5, opacity: 0.2))").contains("background-color:rgb(128 128 128 / 0.2)"))
        #expect(html("Text(\"a\").background(.clear)").contains("background-color:transparent"))
    }

    @Test func cornerRadius() {
        #expect(html("Text(\"a\").cornerRadius(8)").contains("border-radius:8px;overflow:hidden"))
    }

    @Test func frame() {
        let fixed = html("Text(\"a\").frame(width: 100, height: 50)")
        #expect(fixed.hasPrefix(#"<div class="layer" style="display:flex;align-items:center;justify-content:center;width:100px;flex-shrink:0;height:50px"#))
        let aligned = html("Text(\"a\").frame(maxWidth: 300, alignment: .leading)")
        #expect(aligned.contains("justify-content:flex-start;max-width:300px;margin-inline:auto"))
        #expect(html("VStack { Text(\"a\").frame(maxWidth: .infinity) }").contains("align-self:stretch"))
        #expect(html("Text(\"a\").frame(minWidth: 10, minHeight: 20)").contains("min-width:10px;min-height:20px"))
    }

    // Modifiers apply in order, so the same modifiers in a different order give different boxes.
    @Test func orderMatters() {
        // padding then background: the background includes the padding (one box).
        let paddedThenBg = html("Text(\"a\").padding().background(.red)")
        #expect(paddedThenBg == #"<div class="text" style="padding:16px;background-color:var(--c-red)">a</div>"#)
        // background then padding: the padding is outside the background (two boxes).
        let bgThenPadded = html("Text(\"a\").background(.red).padding()")
        #expect(bgThenPadded == #"<div class="layer" style="display:flex;align-items:center;justify-content:center;padding:16px"><div class="text" style="background-color:var(--c-red)">a</div></div>"#)
        // frame then background fills the frame; background then frame doesn't.
        let frameThenBg = html("Text(\"a\").frame(width: 100).background(.red)")
        #expect(frameThenBg.hasPrefix(#"<div class="layer""#) && frameThenBg.contains("width:100px;flex-shrink:0;background-color:var(--c-red)"))
        let bgThenFrame = html("Text(\"a\").background(.red).frame(width: 100)")
        #expect(bgThenFrame.contains(#"<div class="text" style="background-color:var(--c-red)">a</div>"#))
        // cornerRadius after background rounds it; before background it doesn't.
        #expect(html("Text(\"a\").background(.red).cornerRadius(4)") == #"<div class="text" style="background-color:var(--c-red);border-radius:4px;overflow:hidden">a</div>"#)
        #expect(html("Text(\"a\").cornerRadius(4).background(.red)").hasPrefix(#"<div class="layer""#))
    }

    @Test func innerModifierWinsForInheritedStyles() {
        let out = html("Text(\"a\").foregroundColor(.red).foregroundColor(.blue)")
        #expect(out.contains("color:var(--c-red)") && !out.contains("--c-blue"))
    }

    @Test func modifiersOnContainersAndCustomViews() {
        let out = html("Card().padding()", extra: "struct Card: View { var body: some View { Text(\"c\") } }")
        #expect(out == #"<div class="text" style="padding:16px">c</div>"#)
    }

    @Test func unsupportedValuesWarnButStillRender() {
        let colorOut = render("Text(\"a\").foregroundColor(.bluee)")
        #expect(colorOut.html == #"<div class="text">a</div>"#)
        let d = colorOut.diagnostics.first
        #expect(d?.severity == .warning)
        #expect(d?.message.contains("isn’t a supported color") == true)
        #expect(d?.suggestion == "Did you mean “.blue”?")
        #expect(d?.location.line == 5)
        #expect(render("Text(\"a\").font(.huge)").diagnostics.count == 1)
        #expect(render("Text(\"a\").padding(.diagonal)").diagnostics.count == 1)
        #expect(render("VStack(alignment: .top) { Text(\"a\") }").diagnostics.count == 1)
        #expect(render("Text(\"a\").cornerRadius(.zero)").diagnostics.count == 1)
    }
}

// MARK: - State

@Suite struct StateRenderingTests {
    @Test func interpolatedTextCarriesBindingAndInitialValue() {
        let out = render("Text(\"Count: \\(count)\")", state: "@State var count = 3")
        #expect(out.html.contains("Count: 3</div>"))
        #expect(out.html.contains("data-t="))
        #expect(out.statesJSON == #"{"ContentView.count":3}"#)
    }

    @Test func stateJSONCoversAllTypes() {
        let out = render("Text(\"x\")", state: "@State var a = 1.5\n@State var b = \"hi\"\n@State var c = true")
        #expect(out.statesJSON == #"{"ContentView.a":1.5,"ContentView.b":"hi","ContentView.c":true}"#)
    }

    @Test func documentContainsPageParts() {
        let doc = PageTemplate.document(render("Text(\"a\")"))
        #expect(doc.contains("<!doctype html>") && doc.contains(#"<div id="root"><div class="text">a</div></div>"#))
        #expect(doc.contains("Content-Security-Policy") && doc.contains("swui.update(null,"))
        #expect(!PageTemplate.shell.contains(#"class="text""#))
    }

    @Test func stateJSONInDocumentCannotCloseTheScript() {
        let out = render("Text(\"x\")", state: "@State var s = \"</script><b>\"")
        #expect(!PageTemplate.document(out).contains("</script><b>"))
    }
}

// MARK: - Pipeline

@Suite struct RenderPipelineTests {
    private func bigProject() -> String {
        var s = "import SwiftUI\n"
        for i in 0..<45 {
            s += """
            struct Card\(i): View {
                @State var n = 0
                var body: some View {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Title \(i)").font(.headline).foregroundColor(.blue)
                        Text("Count \\(n)").padding(.horizontal)
                        Button("Add") { n += 1 }
                    }
                    .padding().background(Color.gray).cornerRadius(8)
                }
            }

            """
        }
        s += "struct ContentView: View {\n    var body: some View {\n        VStack {\n"
        for i in 0..<45 { s += "            Card\(i)()\n" }
        s += "        }\n    }\n}\n"
        return s
    }

    @Test func parseAndRenderOf500LinesIsFast() {
        let source = bigProject()
        #expect(source.split(separator: "\n").count >= 500)
        _ = HTMLRenderer.render(ViewTreeBuilder.build(source: source, entryView: "ContentView").tree!) // warm up
        let clock = ContinuousClock()
        let elapsed = clock.measure {
            let result = ViewTreeBuilder.build(source: source, entryView: "ContentView")
            #expect(!result.hasErrors)
            let out = HTMLRenderer.render(result.tree!)
            #expect(out.html.count > 10_000)
        }
        #expect(elapsed < .milliseconds(100), "took \(elapsed)")
    }

    @Test func everyPrefixRendersWithoutCrashing() {
        let source = """
        struct ContentView: View {
            @State var count = 0
            var body: some View {
                VStack { Text("n \\(count)").padding().background(.red); Button("+") { count += 1 }; Spacer() }
                    .frame(maxWidth: .infinity)
            }
        }
        """
        var prefix = ""
        for ch in source {
            prefix.append(ch)
            if let tree = ViewTreeBuilder.build(source: prefix, entryView: "ContentView").tree { _ = HTMLRenderer.render(tree) }
        }
    }

    @Test func parseOverridesUseUnsavedText() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir)
        let disk = ProjectParser.parse(project: project)
        #expect(!disk.hasErrors)
        let edited = ProjectParser.parse(project: project, overrides: [
            "ContentView.swift": "struct ContentView: View { var body: some View { Bogus() } }",
            "Extra.swift": "struct Extra: View { var body: some View { Text(\"x\") } }",
        ])
        #expect(edited.errors.first?.code == .unknownView)
        #expect(edited.errors.first?.location.file == "ContentView.swift")
    }

    @Test func assetResolverFindsProjectImages() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swui-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir)
        let assets = project.root.appendingPathComponent("Assets")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: assets.appendingPathComponent("logo.png"))
        let resolve = ProjectAssets.resolver(for: project)
        #expect(resolve("logo") == "data:image/png;base64,AQID")
        #expect(resolve("logo.png") == "data:image/png;base64,AQID")
        #expect(resolve("missing") == nil)
        #expect(resolve("../secret") == nil)
    }
}
