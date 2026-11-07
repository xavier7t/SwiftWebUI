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
    @SceneStorage("showSidebar") private var showSidebar = true
    @SceneStorage("showPreview") private var showPreview = true
    @SceneStorage("sidebarWidth") private var sidebarWidth: Double = PaneLayout.sidebarIdeal
    @SceneStorage("previewWidth") private var previewWidth: Double = 480

    var body: some View {
        HStack(spacing: 0) {
            if showSidebar {
                SidebarPlaceholderView()
                    .frame(width: sidebarWidth)
                PaneDivider(width: $sidebarWidth, minWidth: PaneLayout.sidebarMin, maxWidth: 500, edge: .leading)
            }
            EditorPlaceholderView()
                .frame(minWidth: PaneLayout.editorMin, maxWidth: .infinity)
            if showPreview {
                PaneDivider(width: $previewWidth, minWidth: PaneLayout.previewMin, maxWidth: 1200, edge: .trailing)
                PreviewPlaceholderView()
                    .frame(width: previewWidth)
            }
        }
        .frame(
            minWidth: (showSidebar ? PaneLayout.sidebarMin : 0) + PaneLayout.editorMin + (showPreview ? PaneLayout.previewMin : 0),
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
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { showPreview.toggle() }
                } label: {
                    Label("Toggle Preview", systemImage: "sidebar.trailing")
                }
                .help("Show or hide the preview")
                .keyboardShortcut("0", modifiers: [.command, .option])
            }
        }
        .navigationTitle("SwiftWebUI")
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

struct SidebarPlaceholderView: View {
    var body: some View {
        PlaceholderPane(title: "Sidebar", subtitle: "Project files will appear here", systemImage: "folder")
            .background(.regularMaterial)
    }
}

struct EditorPlaceholderView: View {
    var body: some View {
        PlaceholderPane(title: "Editor", subtitle: "Code editor coming soon", systemImage: "chevron.left.forwardslash.chevron.right")
            .background(Color(nsColor: .textBackgroundColor))
    }
}

struct PreviewPlaceholderView: View {
    var body: some View {
        PlaceholderPane(title: "Preview", subtitle: "Live web preview coming soon", systemImage: "safari")
            .background(Color(nsColor: .windowBackgroundColor))
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
