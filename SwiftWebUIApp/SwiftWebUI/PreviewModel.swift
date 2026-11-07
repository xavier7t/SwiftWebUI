import SwiftUI
import WebKit
import SwiftWebUICore

/// Turns editor changes into a live preview: parse and render off the main thread, drop outdated results,
/// and keep the last good render on screen while the code has errors.
@MainActor @Observable
final class PreviewModel {
    /// Parse and render problems for the whole project, sorted by position.
    private(set) var diagnostics: [Diagnostic] = []
    /// `true` when the code has errors and the page still shows the last render that worked.
    private(set) var isShowingStaleRender = false
    /// `true` once anything has been shown in the page.
    private(set) var hasRender = false

    @ObservationIgnored let host = PreviewWebHost()
    /// How long to wait for further keystrokes before parsing.
    @ObservationIgnored var debounce: Duration = .milliseconds(30)
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var hasGoodRender = false

    struct Computed: Sendable {
        let diagnostics: [Diagnostic]
        let output: RenderOutput?
        let hasErrors: Bool
    }

    /// Schedules a render of `project`, using `override` instead of the file's contents on disk.
    /// A newer request makes any earlier one that hasn't finished irrelevant.
    func requestRender(project: Project, override: (path: String, text: String)?) {
        generation += 1
        let gen = generation
        task?.cancel()
        let delay = debounce
        task = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            let result = await Task.detached(priority: .userInitiated) {
                Self.compute(project: project, override: override)
            }.value
            guard let self, gen == self.generation else { return } // outdated
            self.apply(result)
        }
    }

    nonisolated static func compute(project: Project, override: (path: String, text: String)?) -> Computed {
        let overrides = override.map { [$0.path: $0.text] } ?? [:]
        let parsed = ProjectParser.parse(project: project, overrides: overrides)
        var diagnostics = parsed.diagnostics
        var output: RenderOutput?
        if let tree = parsed.tree {
            let rendered = HTMLRenderer.render(tree, options: RenderOptions(assetResolver: ProjectAssets.resolver(for: project)))
            diagnostics += rendered.diagnostics
            output = rendered
        }
        diagnostics.sort { $0.location < $1.location }
        return Computed(diagnostics: diagnostics, output: output, hasErrors: parsed.hasErrors)
    }

    private func apply(_ result: Computed) {
        diagnostics = result.diagnostics
        if let output = result.output, !result.hasErrors || !hasGoodRender {
            host.show(output)
            hasRender = true
            if !result.hasErrors { hasGoodRender = true }
        }
        isShowingStaleRender = result.hasErrors && hasGoodRender
    }

    func reset() {
        generation += 1
        task?.cancel()
        diagnostics = []
        isShowingStaleRender = false
        hasRender = false
        hasGoodRender = false
        host.clear()
    }
}

/// Owns the `WKWebView`. It loads an empty page once and is then updated in place, so scroll position survives.
@MainActor
final class PreviewWebHost: NSObject, WKNavigationDelegate {
    let webView: WKWebView
    private var isReady = false
    private var latest: RenderOutput?

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .nonPersistent()
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()
        webView.navigationDelegate = self
        loadShell()
    }

    private func loadShell() {
        isReady = false
        webView.loadHTMLString(PageTemplate.shell, baseURL: nil)
    }

    func show(_ output: RenderOutput) {
        latest = output
        push()
    }

    func clear() {
        latest = nil
        guard isReady else { return }
        webView.evaluateJavaScript("swui.update('', {})")
    }

    private func push() {
        guard isReady, let output = latest else { return }
        webView.evaluateJavaScript("swui.update(\(Self.literal(output.html)), \(output.statesJSON))")
    }

    private static func literal(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s], options: [.withoutEscapingSlashes]) else { return "''" }
        return String(String(decoding: data, as: UTF8.self).dropFirst().dropLast())
    }

    // MARK: WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isReady = true
        push()
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { loadShell() }

    /// The page only ever loads itself. Clicked links open in the default browser instead.
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction) async -> WKNavigationActionPolicy {
        if navigationAction.navigationType == .linkActivated {
            if let url = navigationAction.request.url, ["http", "https", "mailto", "tel"].contains(url.scheme?.lowercased() ?? "") {
                NSWorkspace.shared.open(url)
            }
            return .cancel
        }
        return navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel
    }
}
