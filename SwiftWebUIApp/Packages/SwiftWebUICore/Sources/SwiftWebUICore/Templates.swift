import Foundation

/// A starting point for a new project: the source files it begins with.
public struct ProjectTemplate: Hashable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    /// Source files by path relative to the sources folder. `ContentView.swift` is the entry.
    public let files: [String: String]

    public static let blank = ProjectTemplate(
        id: "blank", name: "Hello", summary: "A single line of text.",
        files: ["ContentView.swift": Project.defaultEntrySource])

    public static let landing = ProjectTemplate(
        id: "landing", name: "Landing Page", summary: "A hero, three features and a call to action.",
        files: ["ContentView.swift": """
        import SwiftUI

        struct ContentView: View {
            var body: some View {
                VStack(spacing: 32) {
                    Hero()
                    ScrollView(.horizontal) {
                        HStack(spacing: 16) {
                            Feature(symbol: "bolt.fill", title: "Fast", detail: "Edit and see it right away.")
                            Feature(symbol: "star.fill", title: "Simple", detail: "Write code you already know.")
                            Feature(symbol: "globe", title: "Static", detail: "Export a site to host anywhere.")
                        }
                    }
                    Link("Get started", destination: "https://example.com")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(12)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                .padding(32)
            }
        }

        """, "Hero.swift": """
        import SwiftUI

        struct Hero: View {
            var body: some View {
                VStack(spacing: 8) {
                    Text("Build your site")
                        .font(.largeTitle)
                        .foregroundStyle(LinearGradient(colors: [.blue, .purple], startPoint: .leading, endPoint: .trailing))
                    Text("A landing page written in SwiftUI style.")
                        .font(.title3)
                        .foregroundColor(.gray)
                }
            }
        }

        """, "Feature.swift": """
        import SwiftUI

        struct Feature: View {
            let symbol: String
            let title: String
            let detail: String

            var body: some View {
                VStack(spacing: 8) {
                    Image(systemName: symbol)
                        .font(.title)
                        .foregroundColor(.blue)
                    Text(title)
                        .font(.headline)
                    Text(detail)
                        .foregroundColor(.gray)
                }
                .padding(16)
                .frame(width: 200)
                .background(Color.gray.opacity(0.15))
                .cornerRadius(12)
            }
        }

        """])

    public static let counter = ProjectTemplate(
        id: "counter", name: "Counter", summary: "Buttons that change @State.",
        files: ["ContentView.swift": """
        import SwiftUI

        struct ContentView: View {
            @State private var count = 0

            var body: some View {
                VStack(spacing: 16) {
                    Text("Count: \\(count)")
                        .font(.largeTitle)
                    HStack(spacing: 12) {
                        Button("−") { count -= 1 }
                        Button("+") { count += 1 }
                        Button("Reset") { count = 0 }
                    }
                    .font(.title2)
                }
                .padding()
            }
        }

        """])

    public static let all: [ProjectTemplate] = [.blank, .landing, .counter]
}
