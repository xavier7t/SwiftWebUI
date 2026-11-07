import Foundation
import Testing
@testable import SwiftWebUICore

private func categories(_ source: String) -> [(String, HighlightCategory)] {
    let ns = source as NSString
    return SyntaxHighlighter.highlight(source).map { (ns.substring(with: NSRange(location: $0.location, length: $0.length)), $0.category) }
}

@Suite struct HighlighterTests {
    @Test func mapsTokens() {
        let r = categories("""
        import SwiftUI
        // hi
        struct A: View {
            @State var n = 42
            var body: some View { Text("x") }
        }
        """)
        func has(_ t: String, _ c: HighlightCategory) -> Bool { r.contains { $0.0 == t && $0.1 == c } }
        #expect(has("import", .keyword))
        #expect(has("struct", .keyword))
        #expect(has("// hi", .comment))
        #expect(has("42", .number))
        #expect(has("x", .string))
        #expect(has("State", .attribute))
        #expect(has("View", .type))
        #expect(has("Text", .type))
    }

    @Test func handlesUnicodeOffsets() {
        let source = "let s = \"héllo 🌍\" // ok"
        let ns = source as NSString
        for span in SyntaxHighlighter.highlight(source) {
            #expect(span.location + span.length <= ns.length)
        }
        #expect(categories(source).contains { $0.0 == "// ok" && $0.1 == .comment })
    }

    @Test func incompleteCodeDoesNotCrash() {
        let source = "struct A: View { var body: some View { VStack { Text(\"a"
        for i in 0...source.count { _ = SyntaxHighlighter.highlight(String(source.prefix(i))) }
    }

    @Test func largeFileHighlightsQuickly() {
        let block = """
        struct Row\u{0}: View {
            @State private var count = 0
            var body: some View {
                VStack(spacing: 8) {
                    Text("Row \\(count)").font(.title).padding()
                    Button("Add") { count += 1 } // comment
                }
            }
        }

        """
        let source = (0..<250).map { block.replacingOccurrences(of: "\u{0}", with: "\($0)") }.joined()
        #expect(source.split(separator: "\n").count >= 2000)
        _ = SyntaxHighlighter.highlight(source) // warm up
        let clock = ContinuousClock()
        let full = clock.measure { _ = SyntaxHighlighter.highlight(source) }
        print("full highlight of 2000+ lines:", full)
        // Incremental edits re-highlight just the edited region; the editor does this on a windowed slice.
        let ns = source as NSString
        let window = ns.lineRange(for: NSRange(location: ns.length / 2, length: 0))
        let slice = ns.substring(with: NSRange(location: max(0, window.location - 1500), length: 3000))
        let incremental = clock.measure { _ = SyntaxHighlighter.highlight(slice) }
        print("incremental slice highlight:", incremental)
        #expect(incremental < .milliseconds(16))
    }
}

@Suite struct IndentationTests {
    @Test func newlineKeepsIndentAndIndentsAfterBrace() {
        let e = Indentation.newline(in: "    foo {", selection: NSRange(location: 9, length: 0))
        #expect(e.replacement == "\n        ")
        let e2 = Indentation.newline(in: "    foo", selection: NSRange(location: 7, length: 0))
        #expect(e2.replacement == "\n    ")
    }

    @Test func newlineBetweenBracketsSplits() {
        let e = Indentation.newline(in: "{}", selection: NSRange(location: 1, length: 0))
        #expect(e.replacement == "\n    \n")
        #expect(e.caretOffsetInReplacement == 5)
    }

    @Test func autoClosesAndSkips() {
        #expect(Indentation.typed("(", in: "", selection: NSRange(location: 0, length: 0))?.replacement == "()")
        #expect(Indentation.typed(")", in: "()", selection: NSRange(location: 1, length: 0))?.range == NSRange(location: 1, length: 1))
        #expect(Indentation.typed("(", in: "x", selection: NSRange(location: 0, length: 0)) == nil)
        #expect(Indentation.typed("\"", in: "a", selection: NSRange(location: 1, length: 0)) == nil)
        #expect(Indentation.typed("[", in: "abc", selection: NSRange(location: 0, length: 3))?.replacement == "[abc]")
    }

    @Test func backspaceDeletesPair() {
        #expect(Indentation.backspace(in: "()", selection: NSRange(location: 1, length: 0))?.range == NSRange(location: 0, length: 2))
        #expect(Indentation.backspace(in: "(a)", selection: NSRange(location: 1, length: 0)) == nil)
    }

    @Test func closerOutdents() {
        let e = Indentation.outdentForCloser("}", in: "        ", selection: NSRange(location: 8, length: 0))
        #expect(e?.replacement == "    }")
    }
}

@MainActor @Suite struct OpenFileSessionTests {
    private func temp(_ contents: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("A.swift")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @Test func autosavesAfterPause() async throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url, autosaveDelay: .milliseconds(50))
        s.textDidChange("ab")
        #expect(s.isDirty)
        #expect(try String(contentsOf: url, encoding: .utf8) == "a") // not yet
        try await Task.sleep(for: .milliseconds(300))
        #expect(try String(contentsOf: url, encoding: .utf8) == "ab")
        #expect(!s.isDirty)
    }

    @Test func typingKeepsPostponingAutosave() async throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url, autosaveDelay: .milliseconds(150))
        for ch in ["b", "c", "d"] {
            s.textDidChange(s.text + ch)
            try await Task.sleep(for: .milliseconds(60))
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "a")
        try await Task.sleep(for: .milliseconds(400))
        #expect(try String(contentsOf: url, encoding: .utf8) == "abcd")
    }

    @Test func explicitSaveWritesImmediately() throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url, autosaveDelay: .seconds(60))
        s.textDidChange("z")
        #expect(s.save())
        #expect(try String(contentsOf: url, encoding: .utf8) == "z")
    }

    @Test func cleanFileReloadsOnExternalChange() throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url)
        try "outside".write(to: url, atomically: true, encoding: .utf8)
        #expect(s.checkForExternalChange() == .reloaded)
        #expect(s.text == "outside")
    }

    @Test func dirtyFileReportsConflict() throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url, autosaveDelay: .seconds(60))
        s.textDidChange("mine")
        try "theirs".write(to: url, atomically: true, encoding: .utf8)
        #expect(s.checkForExternalChange() == .conflict)
        #expect(s.text == "mine")
        s.reloadFromDisk()
        #expect(s.text == "theirs" && !s.isDirty)
    }

    @Test func ownSaveIsNotAnExternalChange() throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url)
        s.textDidChange("b"); s.save()
        #expect(s.checkForExternalChange() == nil)
    }

    @Test func deletionIsReported() throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url)
        try FileManager.default.removeItem(at: url)
        #expect(s.checkForExternalChange() == .deleted)
    }

    @Test func changesStreamEmitsCurrentThenEdits() async throws {
        let url = try temp("a")
        let s = try OpenFileSession(url: url, autosaveDelay: .seconds(60))
        var it = s.changes().makeAsyncIterator()
        #expect(await it.next() == "a")
        s.textDidChange("ab")
        #expect(await it.next() == "ab")
    }
}
