import Foundation

public struct RenderOptions: Sendable {
    /// Maps an `Image("name")` name to a URL the page can load (e.g. a data URI). `nil` keeps the name as a relative path.
    public var assetResolver: (@Sendable (String) -> String?)?

    public init(assetResolver: (@Sendable (String) -> String?)? = nil) {
        self.assetResolver = assetResolver
    }
}

public struct RenderOutput: Sendable, Equatable {
    /// The markup that goes inside `<div id="root">`.
    public let html: String
    /// Initial `@State` values as a JSON object keyed by state id.
    public let statesJSON: String
    /// Problems found while rendering, such as an unknown color. These are warnings: the page is still rendered.
    public let diagnostics: [Diagnostic]

    public init(html: String, statesJSON: String, diagnostics: [Diagnostic]) {
        self.html = html
        self.statesJSON = statesJSON
        self.diagnostics = diagnostics
    }

    /// A page with nothing in it.
    public static let empty = RenderOutput(html: "", statesJSON: "{}", diagnostics: [])
}

public enum HTMLRenderer {
    public static func render(_ tree: ViewTree, options: RenderOptions = RenderOptions()) -> RenderOutput {
        let builder = HTMLBuilder(tree: tree, options: options)
        return builder.run()
    }
}

// MARK: - Builder

private enum Axis { case row, column, layers }

private struct Result {
    var nodes: [HTMLNode]
    var h: Bool
    var v: Bool
}

final class HTMLBuilder {
    private let tree: ViewTree
    private let options: RenderOptions
    private var states: [String: Value] = [:]
    private var diagnostics: [Diagnostic] = []

    init(tree: ViewTree, options: RenderOptions) {
        self.tree = tree
        self.options = options
        for s in tree.states { states[s.id] = s.initial }
    }

    func run() -> RenderOutput {
        var els = elements(tree.root)
        if els.count > 1 { els = [stackWrapper(els, axis: .column)] }
        let nodes = els.map { el -> HTMLNode in
            var e = el
            place(&e, in: .row)
            return .element(e)
        }
        var seen = Set<Diagnostic>()
        let unique = diagnostics.filter { seen.insert($0).inserted }
        return RenderOutput(html: nodes.map(HTMLElement.serialize).joined(), statesJSON: statesJSON(), diagnostics: unique)
    }

    private func statesJSON() -> String {
        var object: [String: Any] = [:]
        for (id, value) in states { object[id] = jsonValue(value) }
        return json(object)
    }

    // MARK: Warnings

    private func warn(_ message: String, _ suggestion: String?, _ location: CodeLocation) {
        diagnostics.append(Diagnostic(severity: .warning, code: .invalidArgument, message: message,
                                      suggestion: suggestion, location: location))
    }

    // MARK: Elements

    /// The elements for a node, before the parent decides how to place them. Groups, `ForEach` and custom views
    /// have no element of their own, so they can produce several.
    private func elements(_ node: ViewNode) -> [HTMLElement] {
        if node.isCustom || node.kind == "Group" || node.kind == "ForEach" {
            let kids = node.children.flatMap(elements)
            if node.modifiers.isEmpty { return kids }
            guard !kids.isEmpty else { return [] }
            let target = kids.count == 1 ? kids[0] : stackWrapper(kids, axis: .column)
            return [applyModifiers(target, node.modifiers)]
        }
        let base: HTMLElement
        switch node.kind {
        case "VStack": base = stack(node, axis: .column)
        case "HStack": base = stack(node, axis: .row)
        case "ZStack": base = zstack(node)
        case "Spacer": base = spacer(node)
        case "List": base = list(node)
        case "ScrollView": base = scrollView(node)
        case "Color": base = colorView(node)
        case "Text": base = text(node)
        case "Image": base = image(node)
        case "Button": base = button(node)
        case "Link": base = link(node)
        default:
            if Gradients.kinds.contains(node.kind) { base = gradientView(node) }
            else { base = HTMLElement(class: "unknown") }
        }
        return [applyModifiers(base, node.modifiers)]
    }

    /// Renders children in a parent that lays out along `axis`, and reports whether any child grows.
    private func children(_ nodes: [ViewNode], axis: Axis) -> Result {
        var out: [HTMLNode] = []
        var h = false, v = false
        for node in nodes {
            for var el in elements(node) {
                if el.isSpacer {
                    if axis != .column { h = true }
                    if axis != .row { v = true }
                } else {
                    h = h || el.expandsH
                    v = v || el.expandsV
                }
                place(&el, in: axis)
                out.append(.element(el))
            }
        }
        return Result(nodes: out, h: h, v: v)
    }

    /// Adds the styles a child needs to grow, or to stay in the same cell, inside its parent.
    private func place(_ el: inout HTMLElement, in axis: Axis) {
        switch axis {
        case .row:
            if el.isSpacer { el.set("flex", "1 1 0"); return }
            if el.expandsH { el.set("flex-grow", "1") }
            if el.expandsV { el.set("align-self", "stretch") }
        case .column:
            if el.isSpacer { el.set("flex", "1 1 0"); return }
            if el.expandsV { el.set("flex-grow", "1") }
            if el.expandsH { el.set("align-self", "stretch") }
        case .layers:
            el.set("grid-area", "1/1")
            if el.expandsH { el.set("justify-self", "stretch") }
            if el.expandsV { el.set("align-self", "stretch") }
        }
    }

    private func stackWrapper(_ els: [HTMLElement], axis: Axis) -> HTMLElement {
        var wrapper = HTMLElement(class: axis == .column ? "vstack" : "hstack")
        wrapper.set("display", "flex")
        wrapper.set("flex-direction", axis == .column ? "column" : "row")
        wrapper.set("align-items", "center")
        wrapper.set("justify-content", "center")
        for var el in els {
            if el.isSpacer { wrapper.expandsV = wrapper.expandsV || axis == .column; wrapper.expandsH = wrapper.expandsH || axis == .row }
            else { wrapper.expandsH = wrapper.expandsH || el.expandsH; wrapper.expandsV = wrapper.expandsV || el.expandsV }
            place(&el, in: axis)
            wrapper.children.append(.element(el))
        }
        return wrapper
    }

    // MARK: Layout views

    private func stack(_ node: ViewNode, axis: Axis) -> HTMLElement {
        var el = HTMLElement(class: axis == .column ? "vstack" : "hstack")
        el.set("display", "flex")
        el.set("flex-direction", axis == .column ? "column" : "row")
        var crossAlign = "center"
        var spacing = 8.0
        for arg in node.arguments {
            switch arg.label {
            case "spacing":
                if case .number(let n) = arg.value { spacing = n } else { warn("Spacing must be a number.", "Write it like spacing: 8.", node.location) }
            case "alignment":
                let name: String?
                if case .member(_, let n, _) = arg.value { name = n } else { name = nil }
                if let name, let a = Palette.alignment(named: name),
                   let n = axis == .column ? a.h : a.v {
                    crossAlign = Palette.flexValue(n)
                    if name.hasSuffix("TextBaseline") { crossAlign = "baseline" }
                } else {
                    let valid = axis == .column ? ".leading, .center or .trailing" : ".top, .center or .bottom"
                    warn("“\(arg.value)” isn’t a valid alignment here.", "Use \(valid).", node.location)
                }
            default: break
            }
        }
        el.set("align-items", crossAlign)
        el.set("justify-content", "center")
        el.set("gap", px(spacing))
        let r = children(node.children, axis: axis)
        el.children = r.nodes
        el.expandsH = r.h
        el.expandsV = r.v
        return el
    }

    private func zstack(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "zstack")
        el.set("display", "grid")
        var h = 0, v = 0
        if let arg = node.arguments.first(where: { $0.label == "alignment" }) {
            if case .member(_, let name, _) = arg.value, let a = Palette.alignment(named: name) {
                h = a.h ?? 0; v = a.v ?? 0
            } else {
                warn("“\(arg.value)” isn’t a valid alignment.", "Use something like .center or .topLeading.", node.location)
            }
        }
        el.set("justify-items", Palette.gridValue(h))
        el.set("align-items", Palette.gridValue(v))
        let r = children(node.children, axis: .layers)
        el.children = r.nodes
        el.expandsH = r.h
        el.expandsV = r.v
        return el
    }

    private func scrollView(_ node: ViewNode) -> HTMLElement {
        var horizontal = false, vertical = false
        let axisArg = node.arguments.first { $0.label == nil }?.value
        func axis(_ value: Value) {
            if case .member(_, let name, _) = value, name == "horizontal" { horizontal = true }
            else if case .member(_, let name, _) = value, name == "vertical" { vertical = true }
            else { warn("“\(value)” isn’t a valid scroll axis.", "Use .vertical, .horizontal or [.horizontal, .vertical].", node.location) }
        }
        switch axisArg {
        case .array(let items)?: items.forEach(axis)
        case let value?: axis(value)
        case nil: vertical = true
        }
        if !horizontal && !vertical { vertical = true }

        var el = HTMLElement(class: "scroll")
        el.set("overflow-x", horizontal ? "auto" : "hidden")
        el.set("overflow-y", vertical ? "auto" : "hidden")
        el.set("min-width", "0")
        el.set("min-height", "0")
        el.expandsH = horizontal
        el.expandsV = vertical
        // Content larger than the scroll view must not make the parents grow with it.
        if horizontal { el.set("contain", "inline-size") }

        // The content is laid out at its natural size, so it can be larger than the scroll view.
        var content = HTMLElement(class: "scroll-content")
        content.set("display", "flex")
        content.set("flex-direction", "column")
        content.set("align-items", "center")
        content.set("justify-content", "center")
        if horizontal { content.set("width", "max-content"); content.set("min-width", "100%") }
        if vertical { content.set("min-height", "100%") }
        content.children = children(node.children, axis: .column).nodes
        el.children = [.element(content)]
        return el
    }

    /// A color used as a view fills the space it is given.
    private func colorView(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "color")
        el.expandsH = true
        el.expandsV = true
        let value: Value
        if case let first? = node.arguments.first, first.label == nil { value = first.value }
        else { value = .member(base: "Color", name: "init", arguments: node.arguments) }
        if let color = Palette.color(value) {
            el.set("background-color", color)
        } else {
            let hint = value.description.split(whereSeparator: { !$0.isLetter }).last.map(String.init)
                .flatMap { Suggest.closest(to: $0, in: Palette.colorNames) }.map { "Did you mean “.\($0)”?" }
                ?? "Use a color such as .blue, Color.red or Color(red: 0.1, green: 0.2, blue: 0.3)."
            warn("“\(value)” isn’t a supported color.", hint, node.location)
        }
        return el
    }

    /// A gradient used as a view fills the space it is given.
    private func gradientView(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "gradient")
        el.expandsH = true
        el.expandsV = true
        switch Gradients.build(kind: node.kind, args: node.arguments) {
        case .css(let css): el.set("background-image", css)
        case .invalid(let message, let hint): warn(message, hint, node.location)
        case .notGradient: break
        }
        return el
    }

    private func spacer(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "spacer")
        el.isSpacer = true
        el.expandsH = true
        el.expandsV = true
        if case .number(let n)? = node.arguments.first(where: { $0.label == "minLength" })?.value {
            el.set("min-width", px(n))
            el.set("min-height", px(n))
        }
        return el
    }

    private func list(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "list")
        el.attribute("role", "list")
        el.expandsH = true
        el.expandsV = true
        for child in node.children {
            for var content in elements(child) {
                var row = HTMLElement(class: "row")
                row.attribute("role", "listitem")
                place(&content, in: .row)
                row.children = [.element(content)]
                el.children.append(.element(row))
            }
        }
        return el
    }

    // MARK: Content views

    private func text(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement(class: "text")
        let nodes = textContent(node.arguments.first?.value, into: &el)
        el.children = nodes
        return el
    }

    /// Text content for a value, and a `data-t` binding when it shows `@State` values.
    private func textContent(_ value: Value?, into el: inout HTMLElement) -> [HTMLNode] {
        switch value {
        case .string(let s)?: return [.text(s)]
        case .number(let n)?: return [.text(formatNumber(n))]
        case .bool(let b)?: return [.text(b ? "true" : "false")]
        case .state(let id)?:
            el.attribute("data-t", json([["s", id]]))
            return [.text(display(states[id]))]
        case .interpolated(let parts)?:
            var shown = ""
            var binding: [[String]] = []
            for part in parts {
                switch part {
                case .literal(let s): shown += s; binding.append(["l", s])
                case .state(let id): shown += display(states[id]); binding.append(["s", id])
                }
            }
            el.attribute("data-t", json(binding))
            return [.text(shown)]
        default: return []
        }
    }

    private func display(_ value: Value?) -> String {
        switch value {
        case .string(let s)?: return s
        case .number(let n)?: return formatNumber(n)
        case .bool(let b)?: return b ? "true" : "false"
        case nil: return ""
        case let other?: return other.description
        }
    }

    private func image(_ node: ViewNode) -> HTMLElement {
        if case .string(let symbol)? = node.arguments.first(where: { $0.label == "systemName" })?.value {
            var el = HTMLElement("span", class: "sym")
            el.attribute("role", "img")
            el.attribute("aria-label", symbol)
            el.children = [.text(Palette.symbols[symbol] ?? "◻︎")]
            return el
        }
        var el = HTMLElement("img", class: "image")
        let name: String
        if case .string(let s)? = node.arguments.first?.value { name = s } else { name = "" }
        let src: String
        if name.hasPrefix("https://") || name.hasPrefix("http://") { src = name }
        else { src = options.assetResolver?(name) ?? name }
        el.attribute("src", src)
        el.attribute("alt", name)
        return el
    }

    private func button(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement("button", class: "button")
        el.attribute("type", "button")
        if !node.actions.isEmpty { el.attribute("data-a", json(node.actions.map(actionJSON))) }
        if node.children.isEmpty {
            var title = HTMLElement("span")
            let nodes = textContent(node.arguments.first?.value, into: &title)
            if title.attributes.isEmpty { el.children = nodes } else { title.children = nodes; el.children = [.element(title)] }
        } else {
            el.children = children(node.children, axis: .row).nodes
        }
        return el
    }

    private func link(_ node: ViewNode) -> HTMLElement {
        var el = HTMLElement("a", class: "link")
        var href = "#"
        if case .string(let url)? = node.arguments.first(where: { $0.label == "destination" })?.value {
            if Self.isSafeURL(url) { href = url } else {
                warn("“\(url)” isn’t a supported link.", "Use an https:// or mailto: address, or a relative path.", node.location)
            }
        }
        el.attribute("href", href)
        if node.children.isEmpty {
            var title = HTMLElement("span")
            let nodes = textContent(node.arguments.first(where: { $0.label == nil })?.value, into: &title)
            if title.attributes.isEmpty { el.children = nodes } else { title.children = nodes; el.children = [.element(title)] }
        } else {
            el.children = children(node.children, axis: .row).nodes
        }
        return el
    }

    static func isSafeURL(_ s: String) -> Bool {
        let lower = s.lowercased()
        if let colon = lower.firstIndex(of: ":"), !lower[..<colon].contains("/") {
            return ["http", "https", "mailto", "tel"].contains(String(lower[..<colon]))
        }
        return true
    }

    // MARK: Actions and JSON

    private func actionJSON(_ action: Action) -> [Any] {
        switch action {
        case .add(let state, let amount): return ["add", state, amount]
        case .set(let state, let value): return ["set", state, jsonValue(value)]
        case .toggle(let state): return ["toggle", state]
        }
    }

    private func jsonValue(_ value: Value) -> Any {
        switch value {
        case .string(let s): return s
        case .number(let n): return n
        case .bool(let b): return b
        case .state(let id): return ["s": id]
        default: return value.description
        }
    }

    private func json(_ object: Any) -> String {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])
        else { return "null" }
        return String(decoding: data, as: UTF8.self)
    }

    // MARK: Modifiers

    /// One CSS box. A modifier that would change the meaning of the ones before it starts a new wrapper box,
    /// so `.padding().background(x)` and `.background(x).padding()` look different, as they do in SwiftUI.
    private struct Layer {
        var el: HTMLElement
        var isWrapper = false
        var hasPadding = false
        var hasFrame = false
        var hasBackground = false
        var hasClip = false
    }

    private func applyModifiers(_ base: HTMLElement, _ modifiers: [ModifierNode]) -> HTMLElement {
        var layer = Layer(el: base)
        for m in modifiers { apply(m, to: &layer) }
        return layer.el
    }

    /// Wraps the current box in a new centering flex box and returns the fresh layer.
    private func wrap(_ layer: Layer) -> Layer {
        var inner = layer.el
        place(&inner, in: .row)
        var wrapper = HTMLElement(class: "layer")
        wrapper.set("display", "flex")
        wrapper.set("align-items", "center")
        wrapper.set("justify-content", "center")
        wrapper.expandsH = layer.el.expandsH
        wrapper.expandsV = layer.el.expandsV
        wrapper.children = [.element(inner)]
        return Layer(el: wrapper, isWrapper: true)
    }

    private func apply(_ m: ModifierNode, to layer: inout Layer) {
        switch m.name {
        case "padding": padding(m, &layer)
        case "font":
            guard let value = m.arguments.first?.value else { return }
            guard let font = Palette.font(value) else {
                warn("“\(value)” isn’t a supported font.", "Use a text style like .title or .system(size: 20, weight: .bold).", m.location)
                return
            }
            if layer.el.has("font-size") { return }
            layer.el.set("font-size", px(font.size))
            layer.el.set("font-weight", String(font.weight))
            if font.italic { layer.el.set("font-style", "italic") }
            if let design = font.design { layer.el.set("font-family", design) }
        case "foregroundColor", "foregroundStyle":
            guard let value = m.arguments.first?.value else { return }
            switch Gradients.css(value) {
            case .css(let css):
                if layer.el.has("color") || layer.hasBackground { layer = wrap(layer) }
                layer.el.set("background-image", css)
                layer.el.set("-webkit-background-clip", "text")
                layer.el.set("background-clip", "text")
                layer.el.set("color", "transparent")
                return
            case .invalid(let message, let hint): return warn(message, hint, m.location)
            case .notGradient: break
            }
            guard let color = Palette.color(value) else { return badColor(value, m) }
            if !layer.el.has("color") { layer.el.set("color", color) }
        case "background":
            guard let value = m.arguments.first(where: { $0.label == nil })?.value else { return }
            var fill: (property: String, value: String)
            switch Gradients.css(value) {
            case .css(let css): fill = ("background-image", css)
            case .invalid(let message, let hint): return warn(message, hint, m.location)
            case .notGradient:
                guard let color = Palette.color(value) else { return badColor(value, m) }
                fill = ("background-color", color)
            }
            if layer.hasBackground || layer.hasClip { layer = wrap(layer) }
            layer.el.set(fill.property, fill.value)
            layer.hasBackground = true
        case "cornerRadius":
            guard case .number(let r)? = m.arguments.first?.value else {
                warn("The corner radius must be a number.", "Write it like .cornerRadius(8).", m.location)
                return
            }
            if layer.hasClip { layer = wrap(layer) }
            layer.el.set("border-radius", px(r))
            layer.el.set("overflow", "hidden")
            layer.hasClip = true
        case "frame": frame(m, &layer)
        default: break
        }
    }

    private func badColor(_ value: Value, _ m: ModifierNode) {
        let hint = (value.description.split(whereSeparator: { !$0.isLetter }).last.map(String.init))
            .flatMap { Suggest.closest(to: $0, in: Palette.colorNames) }
            .map { "Did you mean “.\($0)”?" } ?? "Use a color such as .blue, Color.red or Color(red: 0.1, green: 0.2, blue: 0.3)."
        warn("“\(value)” isn’t a supported color.", hint, m.location)
    }

    // MARK: padding

    private func padding(_ m: ModifierNode, _ layer: inout Layer) {
        var edges: Set<String> = ["top", "leading", "bottom", "trailing"]
        var length = 16.0
        for arg in m.arguments {
            switch arg.value {
            case .number(let n): length = n
            case .member(_, let name, _):
                guard let e = Self.edgeSet(name) else { return badEdges(arg.value, m) }
                edges = e
            case .array(let items):
                var all = Set<String>()
                for item in items {
                    guard case .member(_, let name, _) = item, let e = Self.edgeSet(name) else { return badEdges(arg.value, m) }
                    all.formUnion(e)
                }
                edges = all
            default: return badEdges(arg.value, m)
            }
        }
        if layer.hasPadding || layer.hasFrame || layer.hasBackground || layer.hasClip { layer = wrap(layer) }
        layer.hasPadding = true
        let value = px(length)
        if edges.count == 4 {
            layer.el.set("padding", value)
        } else {
            for (edge, css) in [("top", "padding-top"), ("trailing", "padding-right"),
                                ("bottom", "padding-bottom"), ("leading", "padding-left")] where edges.contains(edge) {
                layer.el.set(css, value)
            }
        }
    }

    private func badEdges(_ value: Value, _ m: ModifierNode) {
        warn("“\(value)” isn’t a valid edge set for padding.",
             "Use .all, .horizontal, .vertical, .top, .bottom, .leading or .trailing.", m.location)
    }

    private static func edgeSet(_ name: String) -> Set<String>? {
        switch name {
        case "all": return ["top", "leading", "bottom", "trailing"]
        case "horizontal": return ["leading", "trailing"]
        case "vertical": return ["top", "bottom"]
        case "top", "bottom", "leading", "trailing": return [name]
        default: return nil
        }
    }

    // MARK: frame

    private func frame(_ m: ModifierNode, _ layer: inout Layer) {
        if !(layer.isWrapper && !layer.hasFrame && !layer.hasBackground && !layer.hasClip) { layer = wrap(layer) }
        layer.hasFrame = true
        var alignH = 0, alignV = 0
        var growsH = false, growsV = false
        var fixedH = false, fixedV = false
        for arg in m.arguments {
            guard let label = arg.label else { continue }
            let isInfinity: Bool
            if case .member(_, "infinity", _) = arg.value { isInfinity = true } else { isInfinity = false }
            switch label {
            case "width", "height":
                guard case .number(let n) = arg.value else { warn("“\(label)” must be a number.", "Write it like \(label): 100.", m.location); continue }
                layer.el.set(label, px(n))
                layer.el.set("flex-shrink", "0")
                if label == "width" { fixedH = true } else { fixedV = true }
            case "minWidth", "minHeight":
                guard case .number(let n) = arg.value else { warn("“\(label)” must be a number.", "Write it like \(label): 100.", m.location); continue }
                layer.el.set(label == "minWidth" ? "min-width" : "min-height", px(n))
            case "maxWidth", "maxHeight":
                if isInfinity {
                    if label == "maxWidth" { growsH = true } else { growsV = true }
                } else if case .number(let n) = arg.value {
                    layer.el.set(label == "maxWidth" ? "max-width" : "max-height", px(n))
                    if label == "maxWidth" { layer.el.set("margin-inline", "auto") }
                } else {
                    warn("“\(label)” must be a number or .infinity.", "Write it like \(label): .infinity.", m.location)
                }
            case "alignment":
                if case .member(_, let name, _) = arg.value, let a = Palette.alignment(named: name) {
                    alignH = a.h ?? 0; alignV = a.v ?? 0
                } else {
                    warn("“\(arg.value)” isn’t a valid alignment.", "Use something like .leading or .topTrailing.", m.location)
                }
            default: break // idealWidth, idealHeight
            }
        }
        layer.el.set("justify-content", Palette.flexValue(alignH))
        layer.el.set("align-items", Palette.flexValue(alignV))
        if fixedH { layer.el.expandsH = false }
        if fixedV { layer.el.expandsV = false }
        if growsH { layer.el.expandsH = true }
        if growsV { layer.el.expandsV = true }
    }

    private func px(_ n: Double) -> String { formatNumber(n) + "px" }
}
