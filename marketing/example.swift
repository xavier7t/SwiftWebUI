import SwiftUI

struct ContentView: View {
    @State private var count = 0

    var body: some View {
        VStack(spacing: 0) {
            HeroSection()
            StatsBar()
            FeaturesSection()
            LiveDemo(count: count)
            Footer()
        }
        .background(ink)
    }
}

// MARK: - Palette (computed properties in an extension)
extension ContentView {
    var ink: Color { Color(red: 0.04, green: 0.04, blue: 0.09) }
}

// MARK: - Hero
struct HeroSection: View {
    var body: some View {
        ZStack {
            MeshGradient(
                width: 3, height: 3,
                points: [[0, 0], [0.5, 0], [1, 0],
                         [0, 0.5], [0.5, 0.5], [1, 0.5],
                         [0, 1], [0.5, 1], [1, 1]],
                colors: [.purple, .blue, .indigo,
                         .pink, .purple, .blue,
                         .orange, .pink, .purple]
            )
            VStack(spacing: 20) {
                Text("✦ SwiftWebUI")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(10)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(20)
                Text("Write SwiftUI.")
                    .font(.system(size: 64))
                    .foregroundColor(.white)
                Text("Ship a website.")
                    .font(.system(size: 64))
                    .foregroundStyle(LinearGradient(colors: [.yellow, .orange, .pink],
                                                    startPoint: .leading, endPoint: .trailing))
                Text("Live-preview your SwiftUI-style code as real HTML, then export a static site you can host anywhere.")
                    .font(.title3)
                    .foregroundColor(.white.opacity(0.85))
                    .frame(maxWidth: 560)
                HStack(spacing: 16) {
                    Link("Get started", destination: "https://example.com")
                        .font(.headline)
                        .foregroundColor(.black)
                        .padding(16)
                        .background(Color.white)
                        .cornerRadius(12)
                    Link("View on GitHub", destination: "https://github.com")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(16)
                        .background(Color.white.opacity(0.15))
                        .cornerRadius(12)
                }
            }
            .padding(72)
        }
    }
}

// MARK: - Stats
struct StatsBar: View {
    var body: some View {
        HStack(spacing: 48) {
            Stat(value: "0", label: "Lines of HTML")
            Stat(value: "1", label: "Click to export")
            Stat(value: "∞", label: "Hosts that work")
        }
        .padding(40)
        .frame(maxWidth: .infinity)
        .background(Color.white.opacity(0.04))
    }
}

struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 40))
                .foregroundStyle(LinearGradient(colors: [.cyan, .blue],
                                                startPoint: .top, endPoint: .bottom))
            Text(label)
                .foregroundColor(.gray)
        }
    }
}

// MARK: - Features
struct FeaturesSection: View {
    var body: some View {
        VStack(spacing: 32) {
            Text("Everything you need")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("A small, honest subset of SwiftUI that maps cleanly to the web.")
                .font(.title3)
                .foregroundColor(.gray)
            ScrollView(.horizontal) {
                HStack(spacing: 20) {
                    Feature(symbol: "bolt.fill", title: "Instant preview",
                            detail: "Edit code, see the page update immediately.",
                            from: .orange, to: .pink)
                    Feature(symbol: "square.stack.3d.up.fill", title: "Real layout",
                            detail: "VStack, HStack, ZStack, ScrollView and ForEach.",
                            from: .blue, to: .cyan)
                    Feature(symbol: "paintpalette.fill", title: "Gradients",
                            detail: "Linear, radial, angular, elliptical and mesh.",
                            from: .purple, to: .indigo)
                    Feature(symbol: "globe", title: "Static export",
                            detail: "Deploy to any host. No server required.",
                            from: .green, to: .mint)
                }
                .padding(8)
            }
        }
        .padding(64)
    }
}

struct Feature: View {
    let symbol: String
    let title: String
    let detail: String
    let from: Color
    let to: Color

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 28))
                .foregroundColor(.white)
                .frame(width: 64, height: 64)
                .background(LinearGradient(colors: [from, to],
                                           startPoint: .topLeading, endPoint: .bottomTrailing))
                .cornerRadius(16)
            Text(title)
                .font(.headline)
                .foregroundColor(.white)
            Text(detail)
                .foregroundColor(.gray)
        }
        .padding(28)
        .frame(width: 260)
        .background(Color.white.opacity(0.06))
        .cornerRadius(20)
    }
}

// MARK: - Live demo (@State works in the exported page)
struct LiveDemo: View {
    let count: Int

    var body: some View {
        VStack(spacing: 20) {
            Text("Interactive, too")
                .font(.largeTitle)
                .foregroundColor(.white)
            Text("Buttons mutate @State, right in the browser.")
                .foregroundColor(.gray)
            DemoCounter()
        }
        .padding(64)
        .frame(maxWidth: .infinity)
        .background(RadialGradient(colors: [Color.purple.opacity(0.35), Color.clear],
                                   center: .center, startRadius: 0, endRadius: 360))
    }
}

struct DemoCounter: View {
    @State private var taps = 0

    var body: some View {
        VStack(spacing: 16) {
            Text("\(taps)")
                .font(.system(size: 72))
                .foregroundStyle(LinearGradient(colors: [.pink, .orange],
                                                startPoint: .leading, endPoint: .trailing))
            HStack(spacing: 12) {
                Button("−") { taps -= 1 }
                Button("+") { taps += 1 }
                Button("Reset") { taps = 0 }
            }
            .font(.title2)
        }
        .padding(32)
        .background(Color.white.opacity(0.06))
        .cornerRadius(24)
    }
}

// MARK: - Footer
struct Footer: View {
    var body: some View {
        VStack(spacing: 8) {
            Text("Built with SwiftWebUI — this page is the demo.")
                .foregroundColor(.white)
            Text("Made with SwiftUI syntax, rendered as HTML.")
                .foregroundColor(.gray)
        }
        .padding(48)
        .frame(maxWidth: .infinity)
    }
}