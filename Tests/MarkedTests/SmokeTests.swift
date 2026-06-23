import Testing
@testable import Marked

@Suite("Marked smoke")
struct SmokeTests {
    @Test("module builds and re-exports the parser + engine")
    func builds() {
        let doc = MarkdownParser.parse("# Hi")      // from MarkdownAST, re-exported
        #expect(!doc.blocks.isEmpty)
        _ = MarkdownStyle.default
        _ = TextDocument(blocks: [])                // from MarkdownTextEngine, re-exported
    }
}
