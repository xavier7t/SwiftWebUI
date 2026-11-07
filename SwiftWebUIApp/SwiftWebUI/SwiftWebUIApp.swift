import SwiftUI
import SwiftWebUICore

@main
struct SwiftWebUIApp: App {
    @State private var app = AppState.shared

    var body: some Scene {
        // Declared first so it is the window shown at launch.
        Window("Welcome to SwiftWebUI", id: "welcome") {
            WelcomeView()
        }
        .windowResizability(.contentSize)

        WindowGroup("Project", id: "project", for: URL.self) { $root in
            MainWindowView(root: root)
        }
        .defaultSize(width: 1280, height: 800)
        .commands { ProjectCommands(app: app) }
    }
}

/// File menu: New Project, Open, and Open Recent.
private struct ProjectCommands: Commands {
    var app: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Project…") {
                app.wantsNewProject = true
                openWindow(id: "welcome")
            }
            .keyboardShortcut("n")
            Button("Open Project…") {
                if let folder = app.chooseProjectFolder(), let url = app.prepareToOpen(folder) {
                    openWindow(id: "project", value: url)
                }
            }
            .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(app.recents) { item in
                    Button(item.name) {
                        if let url = app.prepareToOpen(item) { openWindow(id: "project", value: url) }
                        else { openWindow(id: "welcome") }
                    }
                    .disabled(app.missing.contains(item.path))
                }
                Divider()
                Button("Clear Menu") { app.clearRecents() }.disabled(app.recents.isEmpty)
            }
            Divider()
            Button("Welcome Window") { openWindow(id: "welcome") }
        }
    }
}
