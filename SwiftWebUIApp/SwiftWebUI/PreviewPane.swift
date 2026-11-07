import SwiftUI
import WebKit
import SwiftWebUICore

/// The width the preview page is laid out at.
enum PreviewWidth: String, CaseIterable, Identifiable {
    case mobile, tablet, desktop
    var id: String { rawValue }
    /// `nil` fills the pane.
    var points: CGFloat? { switch self { case .mobile: 390; case .tablet: 768; case .desktop: nil } }
    var label: String { switch self { case .mobile: "Mobile"; case .tablet: "Tablet"; case .desktop: "Desktop" } }
    var symbol: String { switch self { case .mobile: "iphone"; case .tablet: "ipad"; case .desktop: "desktopcomputer" } }
}

struct PreviewWebView: NSViewRepresentable {
    let host: PreviewWebHost

    func makeNSView(context: Context) -> WKWebView { host.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The right-hand pane: the live page, with a banner while it shows an older render because the code has errors.
struct PreviewPane: View {
    var model: ProjectModel
    @SceneStorage("previewWidthMode") private var widthMode = PreviewWidth.desktop.rawValue

    var body: some View {
        let preview = model.preview
        let mode = PreviewWidth(rawValue: widthMode) ?? .desktop
        VStack(spacing: 0) {
            URLBar(url: preview.serverURL)
            HStack {
                Picker("Width", selection: $widthMode) {
                    ForEach(PreviewWidth.allCases) { w in
                        Label(w.label, systemImage: w.symbol).tag(w.rawValue)
                    }
                }
                .pickerStyle(.segmented).labelsHidden()
                .labelStyle(.iconOnly)
                .fixedSize()
                .help("Preview width: mobile, tablet or desktop")
                .accessibilityIdentifier("previewWidthPicker")
                if let w = mode.points { Text("\(Int(w)) pt").font(.caption).foregroundStyle(.secondary) }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 6)
            .background(Color(nsColor: .windowBackgroundColor))
            Divider()
            page(preview)
                .frame(maxWidth: mode.points ?? .infinity)
                .frame(maxWidth: .infinity)
                .background(Color(nsColor: .underPageBackgroundColor))
        }
    }

    @ViewBuilder private func page(_ preview: PreviewModel) -> some View {
        ZStack(alignment: .top) {
            PreviewWebView(host: preview.host)
            if !preview.hasRender {
                VStack(spacing: 8) {
                    Image(systemName: "safari").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Preview").font(.headline)
                    Text(model.project == nil ? "Open a project to see it here"
                         : model.isEmptyProject ? "Add a Swift file to see a preview"
                         : preview.diagnostics.contains { $0.severity == .error } ? "Fix the errors to see a preview"
                         : "Nothing to show yet")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
            }
            if preview.isShowingStaleRender {
                Label("Showing the last working preview", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .padding(8)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: preview.isShowingStaleRender)
    }
}

/// Shows the address the preview is served at, with buttons to copy it or open it in the default browser.
struct URLBar: View {
    let url: URL?
    @State private var copied = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe").foregroundStyle(.secondary).font(.caption)
            Text(url?.absoluteString ?? "Starting preview server…")
                .font(.callout.monospaced())
                .foregroundStyle(url == nil ? .secondary : .primary)
                .lineLimit(1).truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                guard let url else { return }
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(url.absoluteString, forType: .string)
                copied = true
                Task { try? await Task.sleep(for: .seconds(1.5)); copied = false }
            } label: {
                Label(copied ? "Copied" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .labelStyle(.iconOnly)
            }
            .help("Copy the URL")
            Button {
                if let url { NSWorkspace.shared.open(url) }
            } label: {
                Label("Open in Browser", systemImage: "arrow.up.forward.app").labelStyle(.iconOnly)
            }
            .help("Open in your default browser")
        }
        .buttonStyle(.borderless)
        .disabled(url == nil)
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

/// A compact list of problems under the editor. Clicking one opens its file and moves the caret there.
struct DiagnosticsPanel: View {
    var model: ProjectModel
    @State private var expanded = true

    var body: some View {
        let diagnostics = model.preview.diagnostics
        if !diagnostics.isEmpty {
            let errors = diagnostics.filter { $0.severity == .error }.count
            let warnings = diagnostics.count - errors
            VStack(spacing: 0) {
                Divider()
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.right").rotationEffect(.degrees(expanded ? 90 : 0)).font(.caption2)
                        if errors > 0 {
                            Label("\(errors) \(errors == 1 ? "error" : "errors")", systemImage: "xmark.octagon.fill")
                                .foregroundStyle(.red)
                        }
                        if warnings > 0 {
                            Label("\(warnings) \(warnings == 1 ? "warning" : "warnings")", systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                        }
                        Spacer()
                    }
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if expanded {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(diagnostics.enumerated()), id: \.offset) { _, d in
                                DiagnosticRow(diagnostic: d) { model.reveal(d) }
                            }
                        }
                    }
                    .frame(maxHeight: 140)
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }
}

private struct DiagnosticRow: View {
    let diagnostic: Diagnostic
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: diagnostic.severity == .error ? "xmark.octagon.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(diagnostic.severity == .error ? .red : .orange)
                    .font(.caption)
                    .padding(.top, 2)
                VStack(alignment: .leading, spacing: 1) {
                    Text(diagnostic.message).font(.callout)
                    if let hint = diagnostic.suggestion {
                        Text(hint).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 8)
                Text("\(diagnostic.location.file):\(diagnostic.location.line)")
                    .font(.caption.monospaced()).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Go to " + diagnostic.location.description)
    }
}
