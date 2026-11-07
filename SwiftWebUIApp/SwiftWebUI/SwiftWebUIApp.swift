import SwiftUI

@main
struct SwiftWebUIApp: App {
    var body: some Scene {
        WindowGroup {
            MainWindowView()
        }
        .defaultSize(width: 1280, height: 800)
    }
}
