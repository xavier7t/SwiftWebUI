import Foundation
import SwiftParser
import SwiftSyntax

/// Visual categories a token can be mapped to. The UI layer decides the colors.
public enum HighlightCategory: Sendable, Equatable, CaseIterable {
    case keyword, string, number, comment, type, attribute, function, plain
}

/// A highlighted range, in UTF-16 offsets (matching `NSString` / `NSTextView`).
public struct HighlightSpan: Sendable, Equatable {
    public let location: Int
    public let length: Int
    public let category: HighlightCategory
}

public enum SyntaxHighlighter {
    /// Highlights the whole source.
    public static func highlight(_ source: String) -> [HighlightSpan] {
        let tree = Parser.parse(source: source)
        var spans: [RawSpan] = []
        for token in tree.tokens(viewMode: .sourceAccurate) {
            let start = token.positionAfterSkippingLeadingTrivia.utf8Offset
            let end = token.endPositionBeforeTrailingTrivia.utf8Offset
            // Trivia: comments.
            var pos = token.position.utf8Offset
            for piece in token.leadingTrivia { appendTrivia(piece, at: &pos, into: &spans) }
            let category = category(for: token)
            if category != .plain, end > start { spans.append(rawSpan(start, end, category)) }
            pos = token.endPositionBeforeTrailingTrivia.utf8Offset
            for piece in token.trailingTrivia { appendTrivia(piece, at: &pos, into: &spans) }
        }
        return convert(spans, in: source)
    }

    /// Highlights only the lines touching `range` (UTF-16), for cheap incremental updates.
    /// Spans are returned in whole-document coordinates.
    public static func highlight(_ source: String, restrictedTo range: NSRange) -> [HighlightSpan] {
        // Parsing is fast enough for the whole file; restricting only trims the output.
        highlight(source).filter { NSIntersectionRange(NSRange(location: $0.location, length: $0.length), range).length > 0 }
    }

    // MARK: Mapping

    static func category(for token: TokenSyntax) -> HighlightCategory {
        switch token.tokenKind {
        case .stringSegment, .stringQuote, .multilineStringQuote, .singleQuote, .rawStringPoundDelimiter,
             .regexLiteralPattern, .regexSlash, .regexPoundDelimiter:
            return .string
        case .integerLiteral, .floatLiteral:
            return .number
        case .keyword:
            return .keyword
        case .identifier:
            if token.parent?.is(AttributeSyntax.self) == true
                || token.parent?.parent?.is(AttributeSyntax.self) == true,
               token.previousToken(viewMode: .sourceAccurate)?.tokenKind == .atSign {
                return .attribute
            }
            if token.parent?.is(IdentifierTypeSyntax.self) == true { return .type }
            if token.parent?.is(DeclReferenceExprSyntax.self) == true {
                if let first = token.text.first, first.isUppercase { return .type }
                if token.nextToken(viewMode: .sourceAccurate)?.tokenKind == .leftParen,
                   token.nextToken(viewMode: .sourceAccurate)?.leadingTrivia.isEmpty == true { return .function }
            }
            if token.parent?.is(MemberTypeSyntax.self) == true { return .type }
            return .plain
        case .atSign, .poundIf, .poundElse, .poundElseif, .poundEndif:
            return .attribute
        case .dollarIdentifier:
            return .plain
        default:
            return .plain
        }
    }

    private static func appendTrivia(_ piece: TriviaPiece, at pos: inout Int, into spans: inout [RawSpan]) {
        let length = piece.sourceLength.utf8Length
        switch piece {
        case .lineComment, .blockComment, .docLineComment, .docBlockComment:
            spans.append(rawSpan(pos, pos + length, .comment))
        default: break
        }
        pos += length
    }

    // MARK: UTF-8 → UTF-16

    private typealias RawSpan = (start: Int, end: Int, category: HighlightCategory)

    private static func rawSpan(_ s: Int, _ e: Int, _ c: HighlightCategory) -> RawSpan { (s, e, c) }

    private static func convert(_ raw: [RawSpan], in source: String) -> [HighlightSpan] {
        let utf8 = Array(source.utf8)
        // Fast path: ASCII means offsets are identical.
        if !utf8.contains(where: { $0 >= 0x80 }) {
            return raw.map { HighlightSpan(location: $0.start, length: $0.end - $0.start, category: $0.category) }
        }
        // Build UTF-8 offset → UTF-16 offset table.
        var table = [Int](repeating: 0, count: utf8.count + 1)
        var u16 = 0, i = 0
        for scalar in source.unicodeScalars {
            let n8 = String(scalar).utf8.count
            for k in 0..<n8 { table[i + k] = u16 }
            i += n8
            u16 += scalar.utf16.count
        }
        table[utf8.count] = u16
        return raw.map {
            let s = table[min($0.start, utf8.count)], e = table[min($0.end, utf8.count)]
            return HighlightSpan(location: s, length: e - s, category: $0.category)
        }
    }
}
