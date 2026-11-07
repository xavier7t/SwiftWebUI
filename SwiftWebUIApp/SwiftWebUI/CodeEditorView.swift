import SwiftUI
import AppKit
import SwiftWebUICore

/// `NSTextView`-backed code editor bound to an `OpenFileSession`.
struct CodeEditorView: NSViewRepresentable {
    let session: OpenFileSession

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NoIntrinsicSizeScrollView()
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = true
        scroll.backgroundColor = .textBackgroundColor
        // Classic TextKit 1 stack, built explicitly so sizing is predictable.
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: NSSize(width: 400, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)
        let textView = CodeTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 400), textContainer: container)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        scroll.documentView = textView

        textView.font = EditorTheme.font
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.insertionPointColor = .controlAccentColor
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 4, height: 8)
        textView.typingAttributes = [.font: EditorTheme.font, .foregroundColor: NSColor.textColor]
        textView.delegate = context.coordinator

        scroll.hasVerticalRuler = true
        scroll.rulersVisible = true
        scroll.verticalRulerView = LineNumberRulerView(textView: textView)

        context.coordinator.attach(textView: textView, session: session)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let textView = scroll.documentView as? NSTextView else { return }
        context.coordinator.attach(textView: textView, session: session)
    }

    // MARK: Coordinator

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        private weak var textView: NSTextView?
        private var session: OpenFileSession?
        private var highlightTask: Task<Void, Never>?
        private var generation = 0
        private var isApplyingExternalText = false
        private var changeTask: Task<Void, Never>?

        /// Per-file undo history, so switching files keeps each file's undo stack.
        private static var undoManagers: [URL: UndoManager] = [:]
        private let fallbackUndo = UndoManager()
        private var currentUndo: UndoManager?

        func attach(textView: NSTextView, session new: OpenFileSession) {
            self.textView = textView
            guard session !== new else { return }
            session?.save()                         // autosave when switching files
            session = new
            (textView as? CodeTextView)?.editHandler = { [weak self] in self?.handleEdit($0) }
            currentUndo = Self.undoManagers[new.url] ?? {
                let m = UndoManager(); Self.undoManagers[new.url] = m; return m
            }()
            (textView as? CodeTextView)?.fileUndoManager = currentUndo
            setText(new.text)
            // Mirror external reloads (session text changes without a user edit).
            changeTask?.cancel()
            changeTask = Task { [weak self, weak new] in
                guard let new else { return }
                for await text in new.changes() {
                    guard let self, self.session === new, let tv = self.textView, tv.string != text else { continue }
                    self.setText(text, preserveSelection: true)
                }
            }
        }

        private func setText(_ text: String, preserveSelection: Bool = false) {
            guard let tv = textView else { return }
            let selection = tv.selectedRange()
            isApplyingExternalText = true
            tv.string = text
            isApplyingExternalText = false
            if preserveSelection {
                tv.setSelectedRange(NSRange(location: min(selection.location, (text as NSString).length), length: 0))
            } else {
                currentUndo?.removeAllActions()
                tv.setSelectedRange(NSRange(location: 0, length: 0))
            }
            fullHighlight(immediately: true)
        }

        func textDidChange(_ notification: Notification) {
            guard !isApplyingExternalText, let tv = textView else { return }
            session?.textDidChange(tv.string)
            highlightEdited()
            fullHighlight(immediately: false)
        }

        // MARK: Edits from Indentation rules

        private func handleEdit(_ edit: TextEdit) {
            guard let tv = textView else { return }
            if tv.shouldChangeText(in: edit.range, replacementString: edit.replacement) {
                tv.textStorage?.replaceCharacters(in: edit.range, with: edit.replacement)
                tv.didChangeText()
                tv.setSelectedRange(NSRange(location: edit.range.location + edit.caretOffsetInReplacement, length: 0))
            }
        }

        // MARK: Highlighting

        /// Cheap synchronous pass over the neighbourhood of the caret so typing never shows stale colors.
        private func highlightEdited() {
            guard let tv = textView, let storage = tv.textStorage else { return }
            let ns = tv.string as NSString
            let caret = min(tv.selectedRange().location, ns.length)
            let start = max(0, caret - 1500), end = min(ns.length, caret + 1500)
            let lines = ns.lineRange(for: NSRange(location: start, length: end - start))
            apply(SyntaxHighlighter.highlight(ns.substring(with: lines)), offset: lines.location, to: storage, range: lines)
        }

        /// Whole-file pass off the main thread; outdated results are dropped.
        private func fullHighlight(immediately: Bool) {
            highlightTask?.cancel()
            generation += 1
            let gen = generation
            guard let tv = textView else { return }
            let source = tv.string
            highlightTask = Task { [weak self] in
                if !immediately { try? await Task.sleep(for: .milliseconds(120)) }
                guard !Task.isCancelled else { return }
                let spans = await Task.detached(priority: .userInitiated) { SyntaxHighlighter.highlight(source) }.value
                guard !Task.isCancelled, let self, gen == self.generation,
                      let tv = self.textView, let storage = tv.textStorage, tv.string == source else { return }
                self.apply(spans, offset: 0, to: storage, range: NSRange(location: 0, length: (source as NSString).length))
            }
        }

        private func apply(_ spans: [HighlightSpan], offset: Int, to storage: NSTextStorage, range: NSRange) {
            storage.beginEditing()
            storage.addAttribute(.foregroundColor, value: NSColor.textColor, range: range)
            for span in spans {
                let r = NSRange(location: span.location + offset, length: span.length)
                guard NSMaxRange(r) <= storage.length else { continue }
                storage.addAttribute(.foregroundColor, value: EditorTheme.color(for: span.category), range: r)
            }
            storage.endEditing()
        }

        func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool { false }
    }
}

/// Text view that routes Return, bracket typing and Backspace through `Indentation`.
final class CodeTextView: NSTextView {
    var editHandler: ((TextEdit) -> Void)?
    var fileUndoManager: UndoManager?

    override var undoManager: UndoManager? { fileUndoManager ?? super.undoManager }

    // The Edit menu's Undo/Redo go through the responder chain to the window's undo manager;
    // handle them here so they use this file's undo history.
    @objc func undo(_ sender: Any?) { fileUndoManager?.undo() }
    @objc func redo(_ sender: Any?) { fileUndoManager?.redo() }

    override func validateUserInterfaceItem(_ item: any NSValidatedUserInterfaceItem) -> Bool {
        switch item.action {
        case #selector(undo(_:)): return fileUndoManager?.canUndo ?? false
        case #selector(redo(_:)): return fileUndoManager?.canRedo ?? false
        default: return super.validateUserInterfaceItem(item)
        }
    }

    override func insertNewline(_ sender: Any?) {
        editHandler?(Indentation.newline(in: string, selection: selectedRange()))
    }

    override func insertText(_ insertString: Any, replacementRange: NSRange) {
        if let s = insertString as? String, s.count == 1, let ch = s.first, replacementRange.location == NSNotFound {
            let sel = selectedRange()
            if let edit = Indentation.outdentForCloser(ch, in: string, selection: sel) ?? Indentation.typed(ch, in: string, selection: sel) {
                editHandler?(edit); return
            }
        }
        super.insertText(insertString, replacementRange: replacementRange)
    }

    override func deleteBackward(_ sender: Any?) {
        if let edit = Indentation.backspace(in: string, selection: selectedRange()) { editHandler?(edit); return }
        super.deleteBackward(sender)
    }

    override func insertTab(_ sender: Any?) {
        editHandler?(TextEdit(range: selectedRange(), replacement: Indentation.unit, caretOffsetInReplacement: Indentation.unit.utf16.count))
    }
}

/// A scroll view that takes whatever size SwiftUI offers instead of its document's size,
/// so the editor never overflows into the sidebar.
final class NoIntrinsicSizeScrollView: NSScrollView {
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric) }
}
