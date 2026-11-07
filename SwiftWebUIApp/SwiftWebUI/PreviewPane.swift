import SwiftUI
import WebKit
import SwiftWebUICore

struct PreviewWebView: NSViewRepresentable {
    let host: PreviewWebHost

    func makeNSView(context: Context) -> WKWebView { host.webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

/// The right-hand pane: the live page, with a banner while it shows an older render because the code has errors.
struct PreviewPane: View {
    var model: ProjectModel

    var body: some View {
        let preview = model.preview
        ZStack(alignment: .top) {
            PreviewWebView(host: preview.host)
            if !preview.hasRender {
                VStack(spacing: 8) {
                    Image(systemName: "safari").font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Preview").font(.headline)
                    Text(model.project == nil ? "Open a project to see it here"
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
