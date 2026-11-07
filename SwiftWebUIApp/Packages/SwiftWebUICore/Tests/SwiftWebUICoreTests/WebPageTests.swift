import Foundation
import Testing
import WebKit
@testable import SwiftWebUICore

/// Loads generated pages into a real `WKWebView` and inspects layout, styles and behavior.
@MainActor
private final class Page: NSObject, WKNavigationDelegate {
    let web: WKWebView
    private var loaded: CheckedContinuation<Void, Never>?

    init(width: CGFloat = 600, height: CGFloat = 400) {
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        super.init()
        web.navigationDelegate = self
    }

    func load(_ html: String) async {
        await withCheckedContinuation { c in
            loaded = c
            web.loadHTMLString(html, baseURL: nil)
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loaded?.resume(); loaded = nil
    }

    @discardableResult
    func eval(_ js: String) async -> Any? {
        try? await web.callAsyncJavaScript(js, contentWorld: .page)
    }

    func number(_ js: String) async -> Double { (await eval("return " + js) as? NSNumber)?.doubleValue ?? .nan }
    func string(_ js: String) async -> String { (await eval("return " + js) as? String) ?? "<nil>" }
}

private func output(_ source: String) -> RenderOutput {
    let r = ViewTreeBuilder.build(source: source, entryView: "ContentView")
    precondition(!r.hasErrors, "\(r.diagnostics)")
    return HTMLRenderer.render(r.tree!)
}

private func page(_ body: String, state: String = "") -> String {
    "struct ContentView: View { \(state)\n var body: some View { \(body) } }"
}

@MainActor @Suite(.serialized) struct WebPageTests {
    @Test func stacksAndSpacersLayOutLikeSwiftUI() async {
        let p = Page(width: 600, height: 400)
        await p.load(PageTemplate.document(output(page("""
        VStack {
            HStack { Text("L").frame(width: 50, height: 20); Spacer(); Text("R").frame(width: 50, height: 20) }
            Spacer()
            Text("Bottom").frame(width: 100, height: 30)
        }
        """))))
        // The row fills the width, so L sits at the left and R at the right.
        #expect(await p.number("document.querySelectorAll('.hstack > .layer')[0].getBoundingClientRect().left") == 0)
        #expect(await p.number("document.querySelectorAll('.hstack > .layer')[1].getBoundingClientRect().right") == 600)
        // The spacer pushes the last row to the bottom edge.
        #expect(await p.number("document.querySelector('.vstack > .layer').getBoundingClientRect().bottom") == 400)
        #expect(await p.number("document.querySelector('.vstack').getBoundingClientRect().height") == 400)
    }

    @Test func contentIsCenteredAndHugs() async {
        let p = Page(width: 600, height: 400)
        await p.load(PageTemplate.document(output(page("Text(\"Hi\").frame(width: 100, height: 40)"))))
        #expect(await p.number("document.querySelector('.layer').getBoundingClientRect().left") == 250)
        #expect(await p.number("document.querySelector('.layer').getBoundingClientRect().top") == 180)
    }

    @Test func stylesAreApplied() async {
        let p = Page()
        await p.load(PageTemplate.document(output(page("""
        Text("Hello").font(.system(size: 20, weight: .bold)).foregroundColor(.red).padding(10).background(Color(red: 0, green: 0, blue: 1)).cornerRadius(6)
        """))))
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).fontSize") == "20px")
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).fontWeight") == "700")
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).paddingLeft") == "10px")
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).borderTopLeftRadius") == "6px")
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).backgroundColor").hasPrefix("rgb(0, 0, 255)"))
        #expect(await p.string("getComputedStyle(document.querySelector('.text')).color").hasPrefix("rgb(255, 59, 48)"))
    }

    @Test func orderedModifiersGiveDifferentSizes() async {
        let p = Page()
        await p.load(PageTemplate.document(output(page("""
        VStack { Text("a").padding(10).background(.red); Text("a").background(.red).padding(10) }
        """))))
        // Padding first: the red box includes the padding. Background first: the red box is just the text.
        let first = await p.string("getComputedStyle(document.querySelectorAll('.text')[0]).backgroundColor")
        let second = await p.string("getComputedStyle(document.querySelectorAll('.text')[1]).backgroundColor")
        #expect(first.hasPrefix("rgb(255, 59, 48)") && second.hasPrefix("rgb(255, 59, 48)"))
        let w0 = await p.number("document.querySelectorAll('.text')[0].getBoundingClientRect().width")
        let w1 = await p.number("document.querySelectorAll('.text')[1].getBoundingClientRect().width")
        #expect(w0 == w1 + 20)
    }

    @Test func clickingAButtonUpdatesState() async {
        let p = Page()
        await p.load(PageTemplate.document(output(page("""
        VStack { Text("Count: \\(count)"); Button("Add") { count += 1 }; Button("Reset") { count = 0 }; Button("Flip") { on.toggle() } }
        """, state: "@State var count = 0\n@State var on = false"))))
        #expect(await p.string("document.querySelector('.text').textContent") == "Count: 0")
        await p.eval("document.querySelectorAll('button')[0].click(); document.querySelectorAll('button')[0].click()")
        #expect(await p.string("document.querySelector('.text').textContent") == "Count: 2")
        await p.eval("document.querySelectorAll('button')[2].click()")
        #expect(await p.string("String(swui.state()['ContentView.on'])") == "true")
        await p.eval("document.querySelectorAll('button')[1].click()")
        #expect(await p.string("document.querySelector('.text').textContent") == "Count: 0")
    }

    @Test func updatingInPlaceKeepsStateAndScroll() async {
        let p = Page(width: 400, height: 300)
        let rows = (0..<60).map { "Text(\"row \($0)\")" }.joined(separator: "; ")
        let source = { (title: String, initial: Int) in
            page("VStack { Text(\"\(title) \\(count)\"); Button(\"Add\") { count += 1 }; \(rows) }", state: "@State var count = \(initial)")
        }
        await p.load(PageTemplate.shell)
        func push(_ o: RenderOutput) async {
            let html = String(decoding: try! JSONSerialization.data(withJSONObject: [o.html]), as: UTF8.self)
            await p.eval("swui.update(JSON.parse(\(jsLiteral(html)))[0], JSON.parse(\(jsLiteral(o.statesJSON))))")
        }
        await push(output(source("A", 0)))
        await p.eval("document.querySelector('button').click(); document.querySelector('button').click(); window.scrollTo(0, 500)")
        let scrolled = await p.number("window.scrollY")
        #expect(scrolled > 0)
        // New code, same state declaration: the DOM node, the count and the scroll position all survive.
        await p.eval("window.keep = document.querySelector('button')")
        await push(output(source("B", 0)))
        #expect(await p.string("document.querySelector('.text').textContent") == "B 2")
        #expect(await p.eval("return window.keep === document.querySelector('button')") as? Bool == true)
        #expect(await p.number("window.scrollY") == scrolled)
        // Changing the initial value resets that state.
        await push(output(source("B", 10)))
        #expect(await p.string("document.querySelector('.text').textContent") == "B 10")
    }

    @Test func pageCannotMakeNetworkRequests() async {
        let p = Page()
        await p.load(PageTemplate.document(output(page("Text(\"x\")"))))
        let blocked = await p.eval("""
        try { await fetch('https://example.com/'); return 'allowed'; } catch (e) { return 'blocked'; }
        """) as? String
        #expect(blocked == "blocked")
    }
}

private func jsLiteral(_ s: String) -> String {
    let data = try! JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes])
    let json = String(decoding: data, as: UTF8.self)
    return String(json.dropFirst().dropLast())
}
