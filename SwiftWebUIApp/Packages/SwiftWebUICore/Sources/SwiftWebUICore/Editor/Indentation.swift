import Foundation

/// Pure text-editing rules for the code editor: auto-indent and bracket handling.
/// All offsets are UTF-16, matching `NSTextView`.
public struct TextEdit: Equatable, Sendable {
    public var range: NSRange
    public var replacement: String
    /// Caret position after the edit, relative to the start of `replacement`.
    public var caretOffsetInReplacement: Int

    public init(range: NSRange, replacement: String, caretOffsetInReplacement: Int) {
        self.range = range
        self.replacement = replacement
        self.caretOffsetInReplacement = caretOffsetInReplacement
    }
}

public enum Indentation {
    public static let unit = "    "
    static let pairs: [Character: Character] = ["{": "}", "(": ")", "[": "]", "\"": "\""]

    /// Edit to apply when the user presses Return with the caret/selection at `selection`.
    public static func newline(in text: String, selection: NSRange) -> TextEdit {
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let linePrefix = ns.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
        let baseIndent = String(linePrefix.prefix { $0 == " " || $0 == "\t" })

        let before = lastNonSpace(in: linePrefix)
        let afterIdx = selection.location + selection.length
        let after: Character? = afterIdx < ns.length ? Character(ns.substring(with: NSRange(location: afterIdx, length: 1))) : nil

        if let before, let closer = pairs[before], before != "\"", after == closer {
            // Caret between a bracket pair: open an indented line and put the closer on its own line.
            let inner = "\n" + baseIndent + unit
            return TextEdit(range: selection, replacement: inner + "\n" + baseIndent, caretOffsetInReplacement: inner.utf16.count)
        }
        let extra = (before == "{" || before == "(" || before == "[") ? unit : ""
        let s = "\n" + baseIndent + extra
        return TextEdit(range: selection, replacement: s, caretOffsetInReplacement: s.utf16.count)
    }

    /// Edit for typing `character`, or nil to let the text view insert it normally.
    public static func typed(_ character: Character, in text: String, selection: NSRange) -> TextEdit? {
        let ns = text as NSString
        let next: Character? = selection.location + selection.length < ns.length
            ? Character(ns.substring(with: NSRange(location: selection.location + selection.length, length: 1))) : nil

        // Typing a closer over an identical auto-inserted closer: skip it.
        if selection.length == 0, let next, next == character, [")", "]", "}", "\""].contains(character) {
            return TextEdit(range: NSRange(location: selection.location, length: 1), replacement: String(character), caretOffsetInReplacement: 1)
        }
        guard let closer = pairs[character] else { return nil }
        if selection.length > 0 {
            // Wrap selection.
            let inner = ns.substring(with: selection)
            return TextEdit(range: selection, replacement: "\(character)\(inner)\(closer)", caretOffsetInReplacement: inner.utf16.count + 2)
        }
        // Don't auto-close a quote next to a word character, or before a non-space/closer.
        if character == "\"" {
            let prev: Character? = selection.location > 0 ? Character(ns.substring(with: NSRange(location: selection.location - 1, length: 1))) : nil
            if let prev, prev.isLetter || prev.isNumber || prev == "\"" { return nil }
        }
        if let next, !next.isWhitespace, ![")", "]", "}"].contains(next) { return nil }
        return TextEdit(range: selection, replacement: "\(character)\(closer)", caretOffsetInReplacement: 1)
    }

    /// Edit for Backspace between an empty bracket pair, deleting both.
    public static func backspace(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location > 0 else { return nil }
        let ns = text as NSString
        guard selection.location < ns.length else { return nil }
        let prev = Character(ns.substring(with: NSRange(location: selection.location - 1, length: 1)))
        let next = Character(ns.substring(with: NSRange(location: selection.location, length: 1)))
        guard pairs[prev] == next else { return nil }
        return TextEdit(range: NSRange(location: selection.location - 1, length: 2), replacement: "", caretOffsetInReplacement: 0)
    }

    /// When a lone `}` / `)` / `]` is typed on a whitespace-only line, edit that outdents the line by one unit.
    public static func outdentForCloser(_ character: Character, in text: String, selection: NSRange) -> TextEdit? {
        guard [")", "]", "}"].contains(character), selection.length == 0 else { return nil }
        let ns = text as NSString
        let lineRange = ns.lineRange(for: NSRange(location: selection.location, length: 0))
        let prefix = ns.substring(with: NSRange(location: lineRange.location, length: selection.location - lineRange.location))
        guard !prefix.isEmpty, prefix.allSatisfy({ $0 == " " }), prefix.count >= unit.count else { return nil }
        let newPrefix = String(prefix.dropLast(unit.count))
        return TextEdit(
            range: NSRange(location: lineRange.location, length: prefix.utf16.count),
            replacement: newPrefix + String(character), caretOffsetInReplacement: newPrefix.utf16.count + 1)
    }

    private static func lastNonSpace(in s: String) -> Character? {
        s.last { $0 != " " && $0 != "\t" }
    }
}
