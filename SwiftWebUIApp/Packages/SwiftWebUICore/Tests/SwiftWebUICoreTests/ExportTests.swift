import Foundation
import Testing
import WebKit
@testable import SwiftWebUICore

private let tinyPNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==")!

private func temp() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("swui-\(UUID().uuidString)").resolvingSymlinksInPath()
}

/// Loads an exported folder in a real web view and records script errors and failed resource loads.
@MainActor
private final class ExportedPage: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    let web: WKWebView
    var errors: [String] = []
    private var loaded: CheckedContinuation<Void, Never>?

    override init() {
        let config = WKWebViewConfiguration()
        let capture = WKUserScript(source: """
        window.addEventListener('error', function (e) {
          webkit.messageHandlers.err.postMessage(e.message || ('failed: ' + (e.target && (e.target.src || e.target.href))));
        }, true);
        """, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(capture)
        web = WKWebView(frame: NSRect(x: 0, y: 0, width: 600, height: 400), configuration: config)
        super.init()
        config.userContentController.add(self, name: "err")
        web.navigationDelegate = self
    }

    func load(_ dir: URL) async {
        await withCheckedContinuation { c in
            loaded = c
            web.loadFileURL(dir.appendingPathComponent("index.html"), allowingReadAccessTo: dir)
        }
        try? await Task.sleep(for: .milliseconds(200)) // let images finish loading
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loaded?.resume(); loaded = nil }
    func userContentController(_ c: WKUserContentController, didReceive message: WKScriptMessage) {
        errors.append("\(message.body)")
    }
    func eval(_ js: String) async -> Any? { try? await web.callAsyncJavaScript(js, contentWorld: .page) }
}

@MainActor @Suite(.serialized) struct ExportTests {
    @Test(arguments: ProjectTemplate.all) func templateParsesWithoutErrors(template: ProjectTemplate) throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir, template: template)
        let parsed = ProjectParser.parse(project: project)
        #expect(parsed.errors.isEmpty, "\(parsed.errors)")
        let rendered = HTMLRenderer.render(parsed.tree!)
        #expect(rendered.diagnostics.isEmpty, "\(rendered.diagnostics)")
        #expect(!rendered.html.isEmpty)
    }

    @Test(arguments: ProjectTemplate.all) func exportWritesFilesAndLoadsCleanly(template: ProjectTemplate) async throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir, template: template)
        let out = dir.appendingPathComponent("site")
        let report = try SiteExporter.export(project: project, to: out)
        #expect(Set(report.files).isSuperset(of: ["index.html", "styles.css", "runtime.js"]))
        for f in report.files { #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(f).path)) }
        let html = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
        #expect(html.contains("styles.css") && html.contains("runtime.js"))

        let page = ExportedPage()
        await page.load(out)
        #expect(page.errors.isEmpty, "\(page.errors)")
        #expect((await page.eval("return document.querySelector('#root').children.length") as? NSNumber)?.intValue ?? 0 > 0)
    }

    @Test func exportedButtonsStillWork() async throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir, template: .counter)
        let out = dir.appendingPathComponent("site")
        _ = try SiteExporter.export(project: project, to: out)
        let page = ExportedPage()
        await page.load(out)
        _ = await page.eval("document.querySelectorAll('button')[1].click()")
        #expect(await page.eval("return document.querySelector('.text').textContent") as? String == "Count: 1")
    }

    @Test func imagesAreCopiedAndResolve() async throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir, template: .blank)
        try FileManager.default.createDirectory(at: project.root.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        try tinyPNG.write(to: project.root.appendingPathComponent("Assets/my logo.png"))
        try """
        struct ContentView: View { var body: some View { VStack { Image("my logo"); Image("nope") } } }
        """.write(to: project.sourcesURL.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("site")
        let report = try SiteExporter.export(project: project, to: out)
        #expect(report.files.contains("assets/my logo.png"))
        #expect(report.missingImages == ["nope"])

        // Every local reference in the page points at a file that was written.
        let html = try String(contentsOf: out.appendingPathComponent("index.html"), encoding: .utf8)
        let srcs = html.components(separatedBy: "src=\"").dropFirst().map { String($0.prefix { $0 != "\"" }) }
        for src in srcs where src.hasPrefix("assets/") {
            let path = src.removingPercentEncoding ?? src
            #expect(FileManager.default.fileExists(atPath: out.appendingPathComponent(path).path), "\(src)")
        }
        let page = ExportedPage()
        await page.load(out)
        #expect(await page.eval("return document.querySelector('img').naturalWidth") as? NSNumber == 1)
    }

    @Test func exportRefusesProjectsWithErrors() throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir)
        try "struct ContentView: View { var body: some View { Bogus() } }"
            .write(to: project.sourcesURL.appendingPathComponent("ContentView.swift"), atomically: true, encoding: .utf8)
        let out = dir.appendingPathComponent("site")
        #expect(throws: ExportError.self) { try SiteExporter.export(project: project, to: out) }
        #expect(!FileManager.default.fileExists(atPath: out.path))
    }

    @Test func referenceMatchesRegistry() {
        let names = Reference.entries.map(\.name)
        #expect(names == Registry.views.map(\.name) + Registry.modifiers.map { "." + $0.name })
        #expect(Reference.entries.allSatisfy { !$0.summary.isEmpty && !$0.example.isEmpty })
        #expect(Reference.sections.flatMap(\.entries).count == Reference.entries.count)
    }
}

@MainActor @Suite(.serialized) struct ScrollViewTests {
    @Test func landingTemplateScrollsHorizontallyOnNarrowPages() async throws {
        let dir = temp(); defer { try? FileManager.default.removeItem(at: dir) }
        let project = try Project.create(name: "P", in: dir, template: .landing)
        let out = dir.appendingPathComponent("site")
        _ = try SiteExporter.export(project: project, to: out)
        let page = ExportedPage()
        page.web.frame = NSRect(x: 0, y: 0, width: 390, height: 800)
        await page.load(out)
        let page390 = await page.eval("return document.documentElement.scrollWidth") as? NSNumber
        #expect(page390 == 390, "page overflows: \(String(describing: page390))")
        let scroll = await page.eval("var s=document.querySelector('.scroll'); return [s.scrollWidth, s.clientWidth]") as? [NSNumber]
        #expect((scroll?[0].intValue ?? 0) > (scroll?[1].intValue ?? 0), "\(String(describing: scroll))")
    }

    @Test func scrollViewAxesAndValidation() {
        func parse(_ arg: String) -> ParseResult {
            ViewTreeBuilder.build(source: "struct ContentView: View { var body: some View { ScrollView\(arg) { Text(\"x\") } } }",
                                  entryView: "ContentView")
        }
        for arg in ["", "(.vertical)", "(.horizontal)", "([.horizontal, .vertical])", "(.horizontal, showsIndicators: false)"] {
            let r = parse(arg)
            #expect(!r.hasErrors, "\(arg): \(r.diagnostics)")
            #expect(HTMLRenderer.render(r.tree!).diagnostics.isEmpty, "\(arg)")
        }
        let both = HTMLRenderer.render(parse("([.horizontal, .vertical])").tree!).html
        #expect(both.contains("overflow-x:auto") && both.contains("overflow-y:auto"))
        #expect(HTMLRenderer.render(parse("(.diagonal)").tree!).diagnostics.count == 1)
    }
}
