import Testing
@testable import MarkdownAST

@Suite("Inline code spans")
struct CodeSpanTests {
    @Test("single backtick code span between text")
    func simpleCodeSpan() {
        let out = InlineParser(defs: DefinitionStore()).parse("a `code` b", depth: 0)
        #expect(out == [.text("a "), .code("code"), .text(" b")])
    }

    @Test("double backticks allow a backtick inside")
    func doubleBacktickWithInnerBacktick() {
        let out = InlineParser(defs: DefinitionStore()).parse("``a`b``", depth: 0)
        #expect(out == [.code("a`b")])
    }

    @Test("backslashes are literal inside a code span")
    func backslashLiteralInsideCode() {
        let out = InlineParser(defs: DefinitionStore()).parse("`\\*`", depth: 0)
        #expect(out == [.code("\\*")])
    }

    @Test("unmatched backtick run is literal text")
    func unmatchedBacktickLiteral() {
        let out = InlineParser(defs: DefinitionStore()).parse("`no close", depth: 0)
        #expect(out == [.text("`no close")])
    }

    @Test("one space is stripped from each end when both edges are spaces")
    func spaceTrim() {
        let out = InlineParser(defs: DefinitionStore()).parse("` a `", depth: 0)
        #expect(out == [.code("a")])
    }
}
