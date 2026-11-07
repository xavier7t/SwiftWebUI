import Foundation

/// Colors, fonts and alignments, translated from the values the parser keeps.
enum Palette {
    /// System colors as (light, dark). Exposed to the page as `--c-<name>` custom properties.
    static let systemColors: [(name: String, light: String, dark: String)] = [
        ("red", "#FF3B30", "#FF453A"), ("orange", "#FF9500", "#FF9F0A"), ("yellow", "#FFCC00", "#FFD60A"),
        ("green", "#34C759", "#30D158"), ("mint", "#00C7BE", "#63E6E2"), ("teal", "#30B0C7", "#40C8E0"),
        ("cyan", "#32ADE6", "#64D2FF"), ("blue", "#007AFF", "#0A84FF"), ("indigo", "#5856D6", "#5E5CE6"),
        ("purple", "#AF52DE", "#BF5AF2"), ("pink", "#FF2D55", "#FF375F"), ("brown", "#A2845E", "#AC8E68"),
        ("gray", "#8E8E93", "#8E8E93"),
    ]

    static var colorNames: [String] {
        systemColors.map(\.name) + ["white", "black", "clear", "primary", "secondary", "tertiary", "accentColor"]
    }

    /// A CSS color for a `Color` value, or `nil` when it isn't a supported color.
    static func color(_ value: Value) -> String? {
        switch value {
        case .member(let base, let name, let args):
            guard base == nil || base == "Color" else { return nil }
            if name == "init" { return colorFromComponents(args) }
            guard args.isEmpty else { return nil }
            if systemColors.contains(where: { $0.name == name }) { return "var(--c-\(name))" }
            switch name {
            case "white": return "#FFFFFF"
            case "black": return "#000000"
            case "clear": return "transparent"
            case "primary": return "var(--fg)"
            case "secondary": return "var(--fg-secondary)"
            case "tertiary": return "var(--fg-tertiary)"
            case "accentColor": return "var(--c-blue)"
            default: return nil
            }
        case .method(let inner, let name, let args):
            guard name == "opacity", case .number(let n)? = args.first?.value, args.count == 1,
                  let base = color(inner) else { return nil }
            return "color-mix(in srgb, \(base) \(formatNumber((min(max(n, 0), 1) * 100 * 100).rounded() / 100))%, transparent)"
        default: return nil
        }
    }

    private static func colorFromComponents(_ args: [Argument]) -> String? {
        func number(_ label: String) -> Double? {
            if case .number(let n)? = args.first(where: { $0.label == label })?.value { return n }
            return nil
        }
        let opacity = number("opacity") ?? 1
        func byte(_ n: Double) -> String { formatNumber((min(max(n, 0), 1) * 255).rounded()) }
        let alpha = opacity >= 1 ? "" : " / \(formatNumber((min(max(opacity, 0), 1) * 100).rounded() / 100))"
        if let w = number("white") { return "rgb(\(byte(w)) \(byte(w)) \(byte(w))\(alpha))" }
        if let r = number("red"), let g = number("green"), let b = number("blue") {
            return "rgb(\(byte(r)) \(byte(g)) \(byte(b))\(alpha))"
        }
        return nil
    }

    // MARK: Fonts

    struct FontSpec: Equatable {
        var size: Double
        var weight: Int
        var design: String? // CSS font-family stack
        var italic = false
    }

    static let textStyles: [String: (size: Double, weight: Int)] = [
        "largeTitle": (34, 400), "title": (28, 400), "title2": (22, 400), "title3": (20, 400),
        "headline": (17, 600), "subheadline": (15, 400), "body": (17, 400), "callout": (16, 400),
        "footnote": (13, 400), "caption": (12, 400), "caption2": (11, 400),
    ]

    static let weights: [String: Int] = [
        "ultraLight": 100, "thin": 200, "light": 300, "regular": 400, "medium": 500,
        "semibold": 600, "bold": 700, "heavy": 800, "black": 900,
    ]

    static let designs: [String: String] = [
        "default": "-apple-system,BlinkMacSystemFont,'SF Pro Text','Helvetica Neue',sans-serif",
        "rounded": "ui-rounded,'SF Pro Rounded',-apple-system,sans-serif",
        "serif": "ui-serif,'New York',Georgia,serif",
        "monospaced": "ui-monospace,'SF Mono',Menlo,monospace",
    ]

    static func font(_ value: Value) -> FontSpec? {
        switch value {
        case .member(let base, let name, let args):
            guard base == nil || base == "Font" else { return nil }
            if name == "system" {
                guard case .number(let size)? = args.first(where: { $0.label == "size" })?.value else { return nil }
                var spec = FontSpec(size: size, weight: 400)
                if case .member(_, let w, _)? = args.first(where: { $0.label == "weight" })?.value {
                    guard let weight = weights[w] else { return nil }
                    spec.weight = weight
                }
                if case .member(_, let d, _)? = args.first(where: { $0.label == "design" })?.value {
                    guard let design = designs[d] else { return nil }
                    spec.design = design
                }
                return spec
            }
            if name == "custom" {
                guard case .string(let family)? = args.first?.value,
                      case .number(let size)? = args.first(where: { $0.label == "size" })?.value else { return nil }
                let safe = family.filter { $0 != "'" && $0 != "\"" && $0 != "\\" && $0 != ";" }
                return FontSpec(size: size, weight: 400, design: "'\(safe)',sans-serif")
            }
            guard args.isEmpty, let style = textStyles[name] else { return nil }
            return FontSpec(size: style.size, weight: style.weight)
        case .method(let inner, let name, let args):
            guard var spec = font(inner) else { return nil }
            switch name {
            case "bold": spec.weight = 700
            case "italic": spec.italic = true
            case "monospaced": spec.design = designs["monospaced"]
            case "weight":
                guard case .member(_, let w, _)? = args.first?.value, let weight = weights[w] else { return nil }
                spec.weight = weight
            default: return nil
            }
            return spec
        default: return nil
        }
    }

    // MARK: Alignment

    /// Horizontal (-1 leading, 0 center, 1 trailing) and vertical (-1 top, 0 center, 1 bottom) components.
    struct Alignment2D {
        var h: Int?
        var v: Int?
    }

    static func alignment(named name: String) -> Alignment2D? {
        switch name {
        case "center": return Alignment2D(h: 0, v: 0)
        case "leading": return Alignment2D(h: -1, v: nil)
        case "trailing": return Alignment2D(h: 1, v: nil)
        case "top": return Alignment2D(h: nil, v: -1)
        case "bottom": return Alignment2D(h: nil, v: 1)
        case "topLeading": return Alignment2D(h: -1, v: -1)
        case "topTrailing": return Alignment2D(h: 1, v: -1)
        case "bottomLeading": return Alignment2D(h: -1, v: 1)
        case "bottomTrailing": return Alignment2D(h: 1, v: 1)
        case "firstTextBaseline", "lastTextBaseline": return Alignment2D(h: nil, v: 0)
        default: return nil
        }
    }

    /// CSS `flex-start` / `center` / `flex-end` for -1 / 0 / 1.
    static func flexValue(_ n: Int) -> String { n < 0 ? "flex-start" : (n > 0 ? "flex-end" : "center") }
    /// CSS grid `start` / `center` / `end`.
    static func gridValue(_ n: Int) -> String { n < 0 ? "start" : (n > 0 ? "end" : "center") }

    // MARK: Symbols

    static let symbols: [String: String] = [
        "star": "☆", "star.fill": "★", "heart": "♡", "heart.fill": "♥", "plus": "+", "minus": "−",
        "checkmark": "✓", "xmark": "✕", "chevron.right": "›", "chevron.left": "‹", "chevron.up": "⌃",
        "chevron.down": "⌄", "arrow.right": "→", "arrow.left": "←", "arrow.up": "↑", "arrow.down": "↓",
        "house": "⌂", "house.fill": "⌂", "gear": "⚙︎", "gearshape": "⚙︎", "gearshape.fill": "⚙︎",
        "envelope": "✉︎", "envelope.fill": "✉︎", "person": "👤", "person.fill": "👤", "magnifyingglass": "🔍",
        "bell": "🔔", "bell.fill": "🔔", "trash": "🗑", "trash.fill": "🗑", "bolt": "⚡︎", "bolt.fill": "⚡︎",
        "globe": "🌐", "flag": "⚑", "flag.fill": "⚑", "circle": "○", "circle.fill": "●",
        "square": "□", "square.fill": "■", "sun.max": "☀︎", "sun.max.fill": "☀︎", "moon": "☾", "moon.fill": "☾",
        "phone": "☎︎", "phone.fill": "☎︎", "cart": "🛒", "cart.fill": "🛒", "lock": "🔒", "lock.fill": "🔒",
    ]
}
