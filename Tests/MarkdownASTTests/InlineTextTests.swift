import Testing
@testable import MarkdownAST

@Suite("Inline parser: text & backslash escapes")
struct InlineTextTests {
    @Test("plain text is a single text node")
    func plainText() {
        let out = InlineParser(defs: DefinitionStore()).parse("hello", depth: 0)
        #expect(out == [.text("hello")])
    }

    @Test("backslash escapes ASCII punctuation")
    func backslashEscape() {
        let out = InlineParser(defs: DefinitionStore()).parse("\\*not emphasis\\*", depth: 0)
        #expect(out == [.text("*not emphasis*")])
    }

    @Test("backslash before a normal char is kept literal")
    func backslashBeforeNormalCharKept() {
        let out = InlineParser(defs: DefinitionStore()).parse("a\\b", depth: 0)
        #expect(out == [.text("a\\b")])
    }
}
