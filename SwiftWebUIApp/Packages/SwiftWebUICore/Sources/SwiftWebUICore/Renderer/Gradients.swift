import Foundation

/// Translates SwiftUI gradient values into CSS gradient images.
///
/// Linear gradients are exact on square boxes and for corner-to-corner lines; on other boxes the angle is
/// approximate. Mesh gradients are approximated with overlapping radial gradients, since CSS has no mesh.
enum Gradients {
    enum Outcome: Equatable {
        case notGradient
        case css(String)
        case invalid(message: String, suggestion: String?)
    }

    /// View and value names that create a gradient.
    static let kinds: Set<String> = ["LinearGradient", "RadialGradient", "AngularGradient", "EllipticalGradient", "MeshGradient"]
    /// Types that only appear as arguments of a gradient.
    static let helperTypes: Set<String> = ["Gradient", "UnitPoint", "Angle"]
    private static let staticNames: [String: String] = [
        "linearGradient": "LinearGradient", "radialGradient": "RadialGradient",
        "angularGradient": "AngularGradient", "ellipticalGradient": "EllipticalGradient",
    ]

    /// The CSS for `value` when it is a gradient.
    static func css(_ value: Value) -> Outcome {
        guard case .member(let base, let name, let args) = value else { return .notGradient }
        let kind: String
        if name == "init", let base, kinds.contains(base) || base == "Gradient" { kind = base }
        else if base == nil, let k = staticNames[name] { kind = k }
        else { return .notGradient }
        return build(kind: kind, args: args)
    }

    static func build(kind: String, args: [Argument]) -> Outcome {
        switch kind {
        case "Gradient": return build(kind: "LinearGradient", args: args + [
            Argument(label: "startPoint", value: .member(base: nil, name: "top", arguments: [])),
            Argument(label: "endPoint", value: .member(base: nil, name: "bottom", arguments: []))])
        case "LinearGradient": return linear(args)
        case "RadialGradient": return radial(args)
        case "AngularGradient": return angular(args)
        case "EllipticalGradient": return elliptical(args)
        case "MeshGradient": return mesh(args)
        default: return .notGradient
        }
    }

    // MARK: Pieces

    private struct Failure: Error { let message: String; let suggestion: String? }
    private static func fail(_ m: String, _ s: String? = nil) -> Failure { Failure(message: m, suggestion: s) }

    private static func arg(_ args: [Argument], _ label: String) -> Value? { args.first { $0.label == label }?.value }
    private static func number(_ v: Value?) -> Double? { if case .number(let n)? = v { return n }; return nil }
    private static func pct(_ n: Double) -> String { formatNumber((n * 100).rounded() / 100) + "%" }

    private typealias Stop = (color: String, location: Double)

    /// Color stops from `gradient:`, `stops:` or `colors:`.
    private static func stops(_ args: [Argument]) throws -> [Stop] {
        var source = args
        if let g = arg(args, "gradient") {
            guard case .member(_, "init", let inner) = g else {
                throw fail("“\(g)” isn’t a supported gradient.", "Use Gradient(colors: [.red, .blue]).")
            }
            source = inner
        }
        func color(_ v: Value) throws -> String {
            guard let c = Palette.color(v) else {
                throw fail("“\(v)” isn’t a supported color.", "Use a color such as .blue, Color.red or Color(red: 0.1, green: 0.2, blue: 0.3).")
            }
            return c
        }
        if case .array(let items)? = arg(source, "colors") {
            let colors = try items.map(color)
            guard !colors.isEmpty else { throw fail("A gradient needs at least one color.") }
            return colors.enumerated().map { ($1, colors.count == 1 ? 0 : Double($0) / Double(colors.count - 1)) }
        }
        if case .array(let items)? = arg(source, "stops") {
            let list: [Stop] = try items.map { item in
                guard case .member(_, let name, let a) = item, name == "init" || name == "Stop",
                      let c = a.first(where: { $0.label == "color" })?.value,
                      let l = number(a.first(where: { $0.label == "location" })?.value) else {
                    throw fail("“\(item)” isn’t a gradient stop.", "Use Gradient.Stop(color: .red, location: 0.5).")
                }
                return (try color(c), min(max(l, 0), 1))
            }
            guard !list.isEmpty else { throw fail("A gradient needs at least one stop.") }
            return list
        }
        throw fail("A gradient needs colors.", "Pass colors: [.red, .blue], stops: [...] or gradient: Gradient(colors: [...]).")
    }

    /// A point in the unit square, from `.top`, `.bottomTrailing`, `.zero`, `UnitPoint(x:y:)` and so on.
    private static func point(_ v: Value?, default d: (Double, Double)? = nil, label: String) throws -> (x: Double, y: Double) {
        guard let v else {
            if let d { return d }
            throw fail("A gradient needs “\(label)”.", "For example \(label): .top.")
        }
        if case .member(let base, let name, let a) = v, base == nil || base == "UnitPoint" {
            if name == "init", case .number(let x)? = a.first(where: { $0.label == "x" })?.value,
               case .number(let y)? = a.first(where: { $0.label == "y" })?.value { return (x, y) }
            let table: [String: (Double, Double)] = [
                "zero": (0, 0), "top": (0.5, 0), "bottom": (0.5, 1), "leading": (0, 0.5), "trailing": (1, 0.5),
                "center": (0.5, 0.5), "topLeading": (0, 0), "topTrailing": (1, 0), "bottomLeading": (0, 1),
                "bottomTrailing": (1, 1),
            ]
            if a.isEmpty, let p = table[name] { return p }
        }
        throw fail("“\(v)” isn’t a supported point.", "Use .top, .bottom, .leading, .trailing, .center, .topLeading, .topTrailing, .bottomLeading, .bottomTrailing or UnitPoint(x: 0.2, y: 0.8).")
    }

    /// An angle in degrees, from `.degrees(90)`, `.radians(1)`, `.zero` or `Angle(degrees:)`.
    private static func angle(_ v: Value?, label: String) throws -> Double? {
        guard let v else { return nil }
        if case .member(let base, let name, let a) = v, base == nil || base == "Angle" {
            if name == "zero", a.isEmpty { return 0 }
            if name == "degrees" || (name == "init" && a.first?.label == "degrees"), case .number(let n)? = a.first?.value { return n }
            if name == "radians" || (name == "init" && a.first?.label == "radians"), case .number(let n)? = a.first?.value { return n * 180 / .pi }
        }
        throw fail("“\(v)” isn’t a supported angle.", "Use .degrees(90) or .radians(1.57).")
    }

    private static func list(_ stops: [Stop], position: (Double) -> String) -> String {
        stops.map { "\($0.color) \(position($0.location))" }.joined(separator: ", ")
    }

    private static func run(_ body: () throws -> String) -> Outcome {
        do { return .css(try body()) } catch let f as Failure { return .invalid(message: f.message, suggestion: f.suggestion) }
        catch { return .invalid(message: "This gradient isn’t supported.", suggestion: nil) }
    }

    // MARK: Kinds

    private static func linear(_ args: [Argument]) -> Outcome {
        run {
            let s = try stops(args)
            let a = try point(arg(args, "startPoint"), label: "startPoint")
            let b = try point(arg(args, "endPoint"), label: "endPoint")
            let dx = b.x - a.x, dy = b.y - a.y
            if dx == 0 && dy == 0 { let c = s.last!.color; return "linear-gradient(\(c), \(c))" }
            // Corner to corner: CSS `to bottom right` has the same skewed isolines as SwiftUI.
            if abs(dx) == 1 && abs(dy) == 1 {
                let corner = "\(dy > 0 ? "bottom" : "top") \(dx > 0 ? "right" : "left")"
                return "linear-gradient(to \(corner), \(list(s) { pct($0 * 100) }))"
            }
            var degrees = atan2(dx, -dy) * 180 / .pi
            if degrees < 0 { degrees += 360 }
            let len = (dx * dx + dy * dy).squareRoot()
            let ux = dx / len, uy = dy / len
            let corners = [0.0, ux, uy, ux + uy] // projections of (0,0), (1,0), (0,1), (1,1)
            let lo = corners.min()!, hi = corners.max()!
            let sp = a.x * ux + a.y * uy, ep = b.x * ux + b.y * uy
            return "linear-gradient(\(formatNumber((degrees * 100).rounded() / 100))deg, "
                + list(s) { pct((sp + $0 * (ep - sp) - lo) / (hi - lo) * 100) } + ")"
        }
    }

    private static func radial(_ args: [Argument]) -> Outcome {
        run {
            let s = try stops(args)
            let c = try point(arg(args, "center"), default: (0.5, 0.5), label: "center")
            guard let start = number(arg(args, "startRadius")), let end = number(arg(args, "endRadius")) else {
                throw fail("A radial gradient needs startRadius and endRadius.", "For example startRadius: 0, endRadius: 200.")
            }
            return "radial-gradient(circle farthest-corner at \(pct(c.x * 100)) \(pct(c.y * 100)), "
                + list(s) { formatNumber(((start + $0 * (end - start)) * 100).rounded() / 100) + "px" } + ")"
        }
    }

    private static func elliptical(_ args: [Argument]) -> Outcome {
        run {
            let s = try stops(args)
            let c = try point(arg(args, "center"), default: (0.5, 0.5), label: "center")
            let start = number(arg(args, "startRadiusFraction")) ?? 0
            let end = number(arg(args, "endRadiusFraction")) ?? 0.5
            guard end > 0 else { throw fail("endRadiusFraction must be greater than 0.") }
            let size = pct(end * 100)
            return "radial-gradient(ellipse \(size) \(size) at \(pct(c.x * 100)) \(pct(c.y * 100)), "
                + list(s) { pct((start + $0 * (end - start)) / end * 100) } + ")"
        }
    }

    private static func angular(_ args: [Argument]) -> Outcome {
        run {
            let s = try stops(args)
            let c = try point(arg(args, "center"), default: (0.5, 0.5), label: "center")
            let start = try angle(arg(args, "startAngle") ?? arg(args, "angle"), label: "startAngle") ?? 0
            let end = try angle(arg(args, "endAngle"), label: "endAngle") ?? start
            var span = end - start
            if span <= 0 { span += 360 }
            // SwiftUI measures angles from the +x axis, CSS from the top, both clockwise.
            return "conic-gradient(from \(formatNumber(((start + 90) * 100).rounded() / 100))deg at \(pct(c.x * 100)) \(pct(c.y * 100)), "
                + list(s) { formatNumber(($0 * span * 100).rounded() / 100) + "deg" } + ")"
        }
    }

    private static func mesh(_ args: [Argument]) -> Outcome {
        run {
            guard let w = number(arg(args, "width")), let h = number(arg(args, "height")), w >= 2, h >= 2,
                  w == w.rounded(), h == h.rounded() else {
                throw fail("A mesh gradient needs a whole-number width and height of at least 2.", "For example width: 3, height: 3.")
            }
            guard case .array(let rawPoints)? = arg(args, "points"), case .array(let rawColors)? = arg(args, "colors") else {
                throw fail("A mesh gradient needs points and colors.", "Pass points: [[0, 0], [1, 0], …] and colors: [.red, …].")
            }
            let count = Int(w * h)
            guard rawPoints.count == count, rawColors.count == count else {
                throw fail("A \(Int(w))×\(Int(h)) mesh needs \(count) points and \(count) colors, but has \(rawPoints.count) and \(rawColors.count).")
            }
            var layers: [String] = []
            let reach = pct(1.4 / (max(w, h) - 1) * 100)
            for (p, c) in zip(rawPoints, rawColors) {
                guard case .array(let xy) = p, xy.count == 2, case .number(let x) = xy[0], case .number(let y) = xy[1] else {
                    throw fail("“\(p)” isn’t a mesh point.", "Write each point as [x, y], for example [0.5, 0].")
                }
                guard let color = Palette.color(c) else {
                    throw fail("“\(c)” isn’t a supported color.", "Use a color such as .blue or Color.red.")
                }
                layers.append("radial-gradient(ellipse \(reach) \(reach) at \(pct(x * 100)) \(pct(y * 100)), \(color) 0%, transparent 100%)")
            }
            if let bg = arg(args, "background"), let color = Palette.color(bg) { layers.append("linear-gradient(\(color), \(color))") }
            return layers.joined(separator: ", ")
        }
    }
}
