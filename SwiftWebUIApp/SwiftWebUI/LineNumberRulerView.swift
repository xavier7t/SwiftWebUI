import AppKit
import SwiftWebUICore

/// Vertical ruler showing line numbers next to an `NSTextView`.
final class LineNumberRulerView: NSRulerView {
    private weak var textView: NSTextView?
    /// Lines with problems (1-based), shown as a dot next to the number.
    var problemLines: [Int: Diagnostic.Severity] = [:] { didSet { if problemLines != oldValue { needsDisplay = true } } }
    private let font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)

    init(textView: NSTextView) {
        self.textView = textView
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 40
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                                               name: NSText.didChangeNotification, object: textView)
        NotificationCenter.default.addObserver(self, selector: #selector(needsRedraw),
                                               name: NSView.boundsDidChangeNotification,
                                               object: textView.enclosingScrollView?.contentView)
    }

    required init(coder: NSCoder) { fatalError() }

    @objc private func needsRedraw() { needsDisplay = true }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView, let layout = textView.layoutManager, let container = textView.textContainer else { return }
        // Don't fill `rect`: it can span the whole scroll area and would paint over the text.
        NSColor.separatorColor.setFill()
        NSRect(x: bounds.maxX - 1, y: rect.minY, width: 1, height: rect.height).fill()

        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.secondaryLabelColor]
        let text = textView.string as NSString
        let originY = textView.textContainerOrigin.y
        let visible = layout.glyphRange(forBoundingRect: textView.visibleRect, in: container)
        let visibleChars = layout.characterRange(forGlyphRange: visible, actualGlyphRange: nil)

        // Line number of the first visible line.
        var number = 1
        text.enumerateSubstrings(in: NSRange(location: 0, length: visibleChars.location),
                                 options: [.byLines, .substringNotRequired]) { _, _, _, _ in number += 1 }
        if visibleChars.location > 0, text.character(at: visibleChars.location - 1) == 10 || visibleChars.location == 0 {
            // already counted correctly by the enumeration above
        }

        var index = visibleChars.location
        while index <= NSMaxRange(visibleChars), index <= text.length {
            let lineRange = text.lineRange(for: NSRange(location: min(index, text.length), length: 0))
            let glyph = layout.glyphIndexForCharacter(at: min(lineRange.location, max(text.length - 1, 0)))
            var lineRect = text.length == 0 ? layout.extraLineFragmentRect
                : layout.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
            if lineRange.location == text.length, layout.extraLineFragmentRect != .zero { lineRect = layout.extraLineFragmentRect }
            let y = lineRect.minY + originY - textView.visibleRect.minY
            let label = "\(number)" as NSString
            let size = label.size(withAttributes: attrs)
            label.draw(at: NSPoint(x: ruleThickness - size.width - 8, y: y + (lineRect.height - size.height) / 2), withAttributes: attrs)
            if let severity = problemLines[number] {
                (severity == .error ? NSColor.systemRed : NSColor.systemOrange).setFill()
                NSBezierPath(ovalIn: NSRect(x: 6, y: y + (lineRect.height - 6) / 2, width: 6, height: 6)).fill()
            }
            number += 1
            if NSMaxRange(lineRange) >= text.length {
                // Trailing empty line after a final newline.
                if text.length > 0, text.character(at: text.length - 1) == 10, index < text.length {
                    index = text.length; continue
                }
                break
            }
            index = NSMaxRange(lineRange)
        }
    }
}
