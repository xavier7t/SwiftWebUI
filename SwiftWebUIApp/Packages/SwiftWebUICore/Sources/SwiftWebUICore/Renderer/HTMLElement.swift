import Foundation

/// A node of the generated HTML.
enum HTMLNode {
    case element(HTMLElement)
    case text(String)
}

/// A small HTML element builder. Attributes and styles keep insertion order so output is deterministic.
struct HTMLElement {
    var tag: String
    var attributes: [(name: String, value: String)] = []
    var style: [(name: String, value: String)] = []
    var children: [HTMLNode] = []

    /// Whether the view wants to grow to fill the space it is offered, per axis (like a flexible SwiftUI view).
    var expandsH = false
    var expandsV = false
    /// `Spacer` grows along whichever axis its parent lays out.
    var isSpacer = false

    init(_ tag: String = "div", class cls: String? = nil) {
        self.tag = tag
        if let cls { attributes.append(("class", cls)) }
    }

    mutating func set(_ name: String, _ value: String) {
        if let i = style.firstIndex(where: { $0.name == name }) { style[i].value = value } else { style.append((name, value)) }
    }

    func has(_ name: String) -> Bool { style.contains { $0.name == name } }

    mutating func attribute(_ name: String, _ value: String) {
        if let i = attributes.firstIndex(where: { $0.name == name }) { attributes[i].value = value } else { attributes.append((name, value)) }
    }

    static let voidTags: Set<String> = ["img", "br", "hr", "input"]

    func serialized() -> String {
        var out = "<" + tag
        for a in attributes { out += " \(a.name)=\"\(HTMLElement.escapeAttribute(a.value))\"" }
        if !style.isEmpty {
            out += " style=\"" + HTMLElement.escapeAttribute(style.map { "\($0.name):\($0.value)" }.joined(separator: ";")) + "\""
        }
        out += ">"
        if HTMLElement.voidTags.contains(tag) { return out }
        for c in children { out += HTMLElement.serialize(c) }
        return out + "</\(tag)>"
    }

    static func serialize(_ node: HTMLNode) -> String {
        switch node {
        case .element(let e): return e.serialized()
        case .text(let t): return escapeText(t)
        }
    }

    static func escapeText(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    static func escapeAttribute(_ s: String) -> String {
        escapeText(s).replacingOccurrences(of: "\"", with: "&quot;")
    }
}
