import Testing
@testable import MarkdownAST

@Suite("Bracket / paren matching")
struct BracketMatchTests {
    @Test("matchBracket finds the outer close of nested brackets")
    func nestedBrackets() {
        #expect(matchBracket(Array("[a [b] c]"), openAt: 0) == 8)
    }

    @Test("escaped close bracket is skipped")
    func escapedBracket() {
        // "[a\]b]" — the \] is escaped, so the real close is the last ].
        #expect(matchBracket(Array("[a\\]b]"), openAt: 0) == 5)
    }

    @Test("a bracket inside a code span is opaque")
    func bracketInCodeSpan() {
        // "[a `b[` c]" — the [ inside the code span must not count.
        #expect(matchBracket(Array("[a `b[` c]"), openAt: 0) == 9)
    }

    @Test("matchParen finds the balanced close")
    func balancedParen() {
        #expect(matchParen(Array("(a (b) c)"), openAt: 0) == 8)
    }

    @Test("an unmatched bracket returns nil")
    func unmatchedBracket() {
        #expect(matchBracket(Array("[a b"), openAt: 0) == nil)
    }
}
