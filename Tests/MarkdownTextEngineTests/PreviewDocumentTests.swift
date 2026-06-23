import Testing
@testable import MarkdownTextEngine

@Suite("Preview document")
struct PreviewDocumentTests {
    // The showcase document exercises every block type at once; laying it out
    // is a smoke test that the types compose without crashing.
    @Test("comprehensive preview document lays out without crashing")
    func previewLaysOut() {
        let doc = TextDocument.preview
        #expect(!doc.blocks.isEmpty)

        let layout = LayoutEngine.layout(doc, width: 400)
        #expect(layout.blocks.count == doc.blocks.count)
        #expect(layout.contentSize.height > 0)
        #expect(layout.contentSize.width <= 400)
    }
}
