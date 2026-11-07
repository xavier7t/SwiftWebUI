import SwiftUI
import SwiftWebUICore

/// Pane widths, persisted between launches.
private enum PaneLayout {
    static let sidebarMin: CGFloat = 180
    static let sidebarIdeal: CGFloat = 240
    static let editorMin: CGFloat = 320
    static let previewMin: CGFloat = 320
}

struct MainWindowView: View {
    /// The project this window shows; nil only in previews.
    var root: URL?
    @State private var model = ProjectModel()
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showReference = false
    @SceneStorage("showSidebar") private var showSidebar = true
    @SceneStorage("showPreview") private var showPreview = true
    @SceneStorage("sidebarWidth") private var sidebarWidth: Double = PaneLayout.sidebarIdeal
    @SceneStorage("previewWidth") private var previewWidth: Double = 480

    var body: some View {
        GeometryReader { geo in
            let editorMin = PaneLayout.editorMin
            let sbMax = geo.size.width - editorMin - (showPreview ? PaneLayout.previewMin : 0)
            let sb = showSidebar ? min(sidebarWidth, max(PaneLayout.sidebarMin, sbMax)) : 0
            let pvMax = geo.size.width - editorMin - sb
            let pv = showPreview ? min(previewWidth, max(PaneLayout.previewMin, pvMax)) : 0
            HStack(spacing: 0) {
                if showSidebar {
                    SidebarView(model: model)
                        .frame(width: sb)
                        .clipped()
                    PaneDivider(width: $sidebarWidth, minWidth: PaneLayout.sidebarMin, maxWidth: 500, edge: .leading)
                }
                EditorPane(model: model)
                    .frame(minWidth: 0, maxWidth: .infinity)
                    .clipped()
                if showPreview {
                    PaneDivider(width: $previewWidth, minWidth: PaneLayout.previewMin, maxWidth: 1200, edge: .trailing)
                    PreviewPane(model: model)
                        .frame(width: pv)
                        .clipped()
                }
            }
        }
        .frame(
            minWidth: (showSidebar ? PaneLayout.sidebarMin + 7 : 0) + PaneLayout.editorMin + (showPreview ? PaneLayout.previewMin + 7 : 0),
            minHeight: 400
        )
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showSidebar.toggle() }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
                .help("Show or hide the sidebar")
                .keyboardShortcut("0", modifiers: [.command])
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { showReference = true } label: {
                    Label("Reference", systemImage: "book")
                }
                .help("Supported views and modifiers")
                Button { model.exportSite() } label: {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                .help("Export as a static website")
                .disabled(model.project == nil)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPreview.toggle() }
                } label: {
                    Label("Toggle Preview", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the preview")
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
        .navigationTitle(model.project?.name ?? "SwiftWebUI")
        .onAppear {
            AppState.shared.projectWindowAppeared()
            guard let root, model.project == nil else { return }
            if AppState.shared.ensureAccess(to: root) {
                model.open(root)
            }
            if model.project == nil {
                // Restored window whose project can't be reached any more.
                AppState.shared.errorMessage = "“\(root.lastPathComponent)” can’t be opened. Choose it again from the welcome window."
                dismissWindow()
                openWindow(id: "welcome")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willResignActiveNotification)) { _ in model.saveCurrent() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in model.saveCurrent() }
        .onDisappear {
            model.saveCurrent()
            AppState.shared.projectWindowDisappeared()
            // Closing the last project window brings the welcome window back.
            if AppState.shared.openProjectWindows == 0, !AppState.shared.isTerminating {
                openWindow(id: "welcome")
            }
        }
        .focusedSceneValue(\.exportAction, model.project == nil ? nil : { model.exportSite() })
        .sheet(isPresented: $showReference) { ReferenceView() }
        .alert(exportTitle, isPresented: Binding(
            get: { model.exportOutcome != nil }, set: { if !$0 { model.exportOutcome = nil } })
        ) {
            if case .done(let report)? = model.exportOutcome {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([report.destination]) }
            }
            Button("OK", role: .cancel) {}
        } message: { Text(exportMessage) }
        .alert("File changed on disk", isPresented: Binding(
            get: { model.conflictFileName != nil }, set: { if !$0 { model.conflictFileName = nil } })
        ) {
            Button("Keep My Changes") { model.resolveConflict(keepMine: true) }
            Button("Reload from Disk", role: .destructive) { model.resolveConflict(keepMine: false) }
        } message: {
            Text("“\(model.conflictFileName ?? "")” was modified outside SwiftWebUI, and you have unsaved edits. Keep your version or reload the one on disk?")
        }
    }
}

extension MainWindowView {
    fileprivate var exportTitle: String {
        if case .failed? = model.exportOutcome { return "Export failed" }
        return "Export complete"
    }

    fileprivate var exportMessage: String {
        switch model.exportOutcome {
        case .done(let r):
            var text = "Wrote \(r.files.count) files to “\(r.destination.lastPathComponent)”."
            if !r.missingImages.isEmpty {
                text += "\n\nImages not found: \(r.missingImages.joined(separator: ", ")). Add them to the project’s Assets folder."
            }
            return text
        case .failed(let m): return m
        case nil: return ""
        }
    }
}

struct ExportActionKey: FocusedValueKey { typealias Value = () -> Void }
extension FocusedValues {
    var exportAction: (() -> Void)? {
        get { self[ExportActionKey.self] }
        set { self[ExportActionKey.self] = newValue }
    }
}

/// A draggable vertical divider that resizes the adjacent pane.
private struct PaneDivider: View {
    @Binding var width: Double
    let minWidth: CGFloat
    let maxWidth: CGFloat
    /// `.leading`: the pane is to the left of the divider; `.trailing`: to the right.
    let edge: HorizontalEdge

    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color(nsColor: .separatorColor))
            .frame(width: 1)
            .padding(.horizontal, 3)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { value in
                        let base = startWidth ?? width
                        startWidth = base
                        let delta = edge == .leading ? value.translation.width : -value.translation.width
                        width = min(max(base + delta, minWidth), maxWidth)
                    }
                    .onEnded { _ in startWidth = nil }
            )
    }
}

struct EditorPane: View {
    var model: ProjectModel
    var body: some View {
        VStack(spacing: 0) {
            editor
            DiagnosticsPanel(model: model)
        }
    }

    @ViewBuilder private var editor: some View {
        Group {
            if let session = model.session {
                CodeEditorView(session: session, diagnostics: model.openFileDiagnostics, reveal: model.revealRequest)
                    .id(session.url)
                    .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity)
                    .clipped()
            } else if let error = model.openError {
                PlaceholderPane(title: "Can’t open file", subtitle: error, systemImage: "exclamationmark.triangle")
            } else {
                PlaceholderPane(title: "Editor", subtitle: "Select a file in the sidebar", systemImage: "chevron.left.forwardslash.chevron.right")
            }
        }
        .background(Color(nsColor: .textBackgroundColor))
    }
}

private struct PlaceholderPane: View {
    let title: String
    let subtitle: String
    let systemImage: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(title).font(.headline)
            Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MainWindowView()
}
