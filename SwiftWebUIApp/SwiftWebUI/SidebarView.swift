import SwiftUI
import SwiftWebUICore

struct SidebarView: View {
    @Bindable var model: ProjectModel
    @State private var renameText = ""
    @State private var prompt: NamePrompt?
    @State private var promptText = ""
    @State private var pendingTrash: URL?
    @FocusState private var renameFocused: Bool

    struct NamePrompt: Identifiable {
        enum Kind { case file, folder }
        let id = UUID()
        let kind: Kind
        let folder: URL?
    }

    var body: some View {
        Group {
            if model.project == nil {
                EmptySidebar(model: model)
            } else {
                List(selection: $model.selection) {
                    OutlineGroup(model.tree, children: \.children) { node in
                        row(node)
                    }
                }
                .listStyle(.sidebar)
                .contextMenu { newItemButtons(in: nil) }
                .onDeleteCommand { if let s = model.selection { pendingTrash = s } }
                .onKeyPress(.return) {
                    guard let s = model.selection, model.renaming == nil else { return .ignored }
                    beginRename(s); return .handled
                }
                .safeAreaInset(edge: .bottom) { footer }
            }
        }
        .background(.regularMaterial)
        .alert("Name", isPresented: Binding(get: { prompt != nil }, set: { if !$0 { prompt = nil } }), presenting: prompt) { p in
            TextField(p.kind == .file ? "File.swift" : "Folder", text: $promptText)
            Button("Create") {
                if p.kind == .file { model.createFile(named: promptText, in: p.folder) }
                else { model.createFolder(named: promptText, in: p.folder) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { p in Text(p.kind == .file ? "New file name" : "New folder name") }
        .confirmationDialog(
            "Move “\(pendingTrash?.lastPathComponent ?? "")” to the Trash?",
            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } }),
            titleVisibility: .visible
        ) {
            Button("Move to Trash", role: .destructive) { if let u = pendingTrash { model.trash(u) } }
        }
        .alert("Something went wrong",
               isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") {}
        } message: { Text(model.errorMessage ?? "") }
    }

    @ViewBuilder
    private func row(_ node: FileNode) -> some View {
        if model.renaming == node.url {
            TextField("Name", text: $renameText)
                .focused($renameFocused)
                .onSubmit { commitRename(node.url) }
                .onExitCommand { model.renaming = nil }
                .onAppear { renameFocused = true }
        } else {
            Label(node.name, systemImage: node.isDirectory ? "folder" : "swift")
                .tag(node.url)
                .draggable(node.url)
                .dropDestination(for: URL.self) { urls, _ in
                    guard node.isDirectory else { return false }
                    urls.forEach { model.move($0, into: node.url) }
                    return true
                }
                .contextMenu {
                    newItemButtons(in: node.isDirectory ? node.url : node.url.deletingLastPathComponent())
                    Divider()
                    Button("Rename") { beginRename(node.url) }
                    Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([node.url]) }
                    Divider()
                    Button("Move to Trash", role: .destructive) { pendingTrash = node.url }
                }
        }
    }

    @ViewBuilder
    private func newItemButtons(in folder: URL?) -> some View {
        Button("New File…") { promptText = ""; prompt = .init(kind: .file, folder: folder) }
        Button("New Folder…") { promptText = ""; prompt = .init(kind: .folder, folder: folder) }
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Menu {
                newItemButtons(in: selectedFolder)
            } label: { Image(systemName: "plus") }
            .menuStyle(.borderlessButton).fixedSize()
            Text(model.project?.name ?? "").font(.caption).foregroundStyle(.secondary).lineLimit(1)
            Spacer()
        }
        .padding(8)
        .background(.bar)
    }

    private var selectedFolder: URL? {
        guard let s = model.selection else { return nil }
        let isDir = (try? s.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
        return isDir ? s : s.deletingLastPathComponent()
    }

    private func beginRename(_ url: URL) {
        renameText = url.lastPathComponent
        model.renaming = url
    }

    private func commitRename(_ url: URL) {
        model.renaming = nil
        model.rename(url, to: renameText)
    }
}

private struct EmptySidebar: View {
    let model: ProjectModel
    @State private var showCreate = false
    @State private var name = "My Site"

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "folder").font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No Project Open").font(.headline)
            Text("Open a project folder or create a new one.")
                .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Open Project…") { openProject() }
            Button("New Project…") { showCreate = true }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .alert("New Project", isPresented: $showCreate) {
            TextField("Name", text: $name)
            Button("Choose Location…") { chooseLocation() }
            Button("Cancel", role: .cancel) {}
        } message: { Text("Name your project, then choose where to save it.") }
    }

    private func openProject() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url { model.open(url) }
    }

    private func chooseLocation() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Create Here"
        if panel.runModal() == .OK, let url = panel.url { model.create(name: name, in: url) }
    }
}
