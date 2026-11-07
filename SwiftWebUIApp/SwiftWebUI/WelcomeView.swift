import SwiftUI
import SwiftWebUICore

/// Simple first-run screen: start a project, open one, or pick from recents.
struct WelcomeView: View {
    @Bindable var app = AppState.shared
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var showNewProject = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 16) {
                Image(systemName: "swift")
                    .font(.system(size: 56))
                    .foregroundStyle(.orange)
                Text("SwiftWebUI").font(.largeTitle.bold())
                Text("Write SwiftUI-style code,\nsee it as a web page.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Spacer().frame(height: 8)
                Button { showNewProject = true } label: {
                    Label("New Project…", systemImage: "plus").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("newProjectButton")
                Button { openExisting() } label: {
                    Label("Open Project…", systemImage: "folder").frame(maxWidth: .infinity)
                }
                .controlSize(.large)
                .accessibilityIdentifier("openProjectButton")
            }
            .padding(32)
            .frame(width: 280)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)

            Divider()

            recentList
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 420)
        .sheet(isPresented: $showNewProject) {
            NewProjectSheet { url in open(url) }
        }
        .onAppear { app.refreshRecents(); consumeNewProjectRequest() }
        .onChange(of: app.wantsNewProject) { consumeNewProjectRequest() }
        .alert("Can’t open project", isPresented: Binding(
            get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })
        ) {
            Button("OK") {}
        } message: { Text(app.errorMessage ?? "") }
    }

    private var recentList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Recent Projects").font(.headline).padding([.top, .horizontal], 16).padding(.bottom, 8)
            if app.recents.isEmpty {
                Text("Projects you open will appear here.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(app.recents) { item in
                    RecentRow(item: item, isMissing: app.missing.contains(item.path),
                              open: { if let url = app.prepareToOpen(item) { open(url) } },
                              remove: { app.removeRecent(item) })
                }
                .listStyle(.plain)
                .accessibilityIdentifier("recentList")
            }
        }
    }

    private func consumeNewProjectRequest() {
        if app.wantsNewProject { app.wantsNewProject = false; showNewProject = true }
    }

    private func openExisting() {
        if let folder = app.chooseProjectFolder(), let url = app.prepareToOpen(folder) { open(url) }
    }

    private func open(_ url: URL) {
        openWindow(id: "project", value: url)
        dismissWindow(id: "welcome")
    }
}

private struct RecentRow: View {
    let item: RecentProject
    let isMissing: Bool
    let open: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack {
            Image(systemName: isMissing ? "exclamationmark.triangle.fill" : "folder.fill")
                .foregroundStyle(isMissing ? .orange : .blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.body)
                Text(isMissing ? "Not found — moved or deleted" : (item.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(isMissing ? .orange : .secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer()
            if isMissing {
                Button("Remove", action: remove).controlSize(.small)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { if !isMissing { open() } }
        .contextMenu {
            if !isMissing { Button("Open", action: open) }
            Button("Remove from Recents", action: remove)
        }
        .padding(.vertical, 2)
    }
}

private struct NewProjectSheet: View {
    let onCreated: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = "MySite"
    @State private var location: URL?
    @State private var error: String?

    private var nameError: String? {
        do { try FileNameValidator.validate(name); return nil }
        catch { return (error as? LocalizedError)?.errorDescription ?? error.localizedDescription }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New Project").font(.title2.bold())
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("projectNameField")
            HStack {
                Text(location.map { ($0.path as NSString).abbreviatingWithTildeInPath } ?? "No location chosen")
                    .foregroundStyle(location == nil ? .secondary : .primary)
                    .lineLimit(1).truncationMode(.middle)
                Spacer()
                Button("Choose…") { if let l = AppState.shared.chooseLocation() { location = l } }
                    .accessibilityIdentifier("chooseLocationButton")
            }
            if let message = error ?? (name.isEmpty ? nil : nameError) {
                Text(message).font(.caption).foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Create") { create() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(location == nil || nameError != nil)
                    .accessibilityIdentifier("createProjectButton")
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    private func create() {
        guard let location else { return }
        if let url = AppState.shared.createProject(name: name, in: location) {
            dismiss()
            onCreated(url)
        } else {
            error = AppState.shared.errorMessage
            AppState.shared.errorMessage = nil
        }
    }
}
