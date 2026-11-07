import AppKit
import SwiftWebUICore

/// Maps highlight categories to colors that adapt to light and dark appearance.
enum EditorTheme {
    nonisolated(unsafe) static let font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)

    static func color(for category: HighlightCategory) -> NSColor {
        switch category {
        case .keyword: dynamic(light: (0.68, 0.14, 0.58), dark: (0.99, 0.37, 0.64))
        case .string: dynamic(light: (0.77, 0.10, 0.09), dark: (0.99, 0.42, 0.36))
        case .number: dynamic(light: (0.11, 0.00, 0.81), dark: (0.82, 0.75, 0.40))
        case .comment: dynamic(light: (0.36, 0.42, 0.47), dark: (0.50, 0.55, 0.60))
        case .type: dynamic(light: (0.11, 0.43, 0.46), dark: (0.36, 0.85, 0.89))
        case .attribute: dynamic(light: (0.39, 0.22, 0.12), dark: (0.99, 0.56, 0.25))
        case .function: dynamic(light: (0.20, 0.31, 0.55), dark: (0.40, 0.72, 0.95))
        case .plain: .textColor
        }
    }

    private static func dynamic(light: (CGFloat, CGFloat, CGFloat), dark: (CGFloat, CGFloat, CGFloat)) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        }
    }
}
