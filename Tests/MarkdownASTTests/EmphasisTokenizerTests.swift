import Testing
@testable import MarkdownAST

@Suite("Inline emphasis tokenizer")
struct EmphasisTokenizerTests {
    @Test("`**` is one delimiter token (char *, count 2)")
    func doubleStarDelim() {
        let tokens = InlineParser(defs: DefinitionStore()).tokenize("**")
        #expect(tokens.count == 1)
        guard case .delim(let char, let count, _, _, _) = tokens.first else {
            Issue.record("expected a delimiter token")
            return
        }
        #expect(char == "*")
        #expect(count == 2)
    }

    @Test("text between delimiters is a single literal token")
    func textBetweenDelimsOneLiteral() {
        let tokens = InlineParser(defs: DefinitionStore()).tokenize("*ab*")
        #expect(tokens.count == 3)
        #expect(tokens[1] == .literal(.text("ab")))
    }

    @Test("`~~` is a strikethrough delimiter (char ~, count 2)")
    func doubleTildeDelim() {
        let tokens = InlineParser(defs: DefinitionStore()).tokenize("~~")
        #expect(tokens.count == 1)
        guard case .delim(let char, let count, _, _, _) = tokens.first else {
            Issue.record("expected a delimiter token")
            return
        }
        #expect(char == "~")
        #expect(count == 2)
    }

    @Test("a single `~` is literal text, not a delimiter")
    func singleTildeLiteral() {
        let tokens = InlineParser(defs: DefinitionStore()).tokenize("~")
        #expect(tokens == [.literal(.text("~"))])
    }
}
