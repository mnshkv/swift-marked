import Testing
import CoreGraphics
@testable import Marked

@Suite("BlockMapper — native blocks")
struct BlockMapperTests {

    let ctx = StyleContext(.default, .light)
    var map: ([MarkdownBlock]) -> [Block] {
        { BlockMapper.map($0, ctx: ctx, footnotes: [:]) }
    }

    // MARK: - Task 3.1 tests

    @Test("heading level 2 → bold paragraph at headingSizes[1]")
    func heading() {
        let blocks = map([.heading(level: 2, content: [.text("H")])])
        guard case .paragraph(let p) = blocks.first else {
            Issue.record("Expected .paragraph"); return
        }
        guard case .text(let s, let style) = p.runs.first else {
            Issue.record("Expected .text run"); return
        }
        #expect(s == "H")
        #expect(style.isBold)
        #expect(style.fontSize == ctx.style.headingSizes[1])
    }

    @Test("paragraph → body paragraph style with spacingAfter")
    func paragraph() {
        let blocks = map([.paragraph(content: [.text("p")])])
        guard case .paragraph(let p) = blocks.first else {
            Issue.record("Expected .paragraph"); return
        }
        #expect(p.style.spacingAfter == ctx.style.spacing.paragraphAfter)
        guard case .text(let s, _) = p.runs.first else {
            Issue.record("Expected .text run"); return
        }
        #expect(s == "p")
    }

    @Test("blockQuote → .quote with inner .paragraph")
    func blockQuote() {
        let blocks = map([.blockQuote(blocks: [.paragraph(content: [.text("q")])])])
        guard case .quote(let doc) = blocks.first else {
            Issue.record("Expected .quote"); return
        }
        #expect(doc.blocks.count == 1)
        guard case .paragraph(_) = doc.blocks.first else {
            Issue.record("Expected inner .paragraph"); return
        }
    }

    @Test("codeBlock → lines split by newline, correct language")
    func codeBlock() {
        let blocks = map([.codeBlock(language: "swift", code: "a\nb")])
        guard case .codeBlock(let cb) = blocks.first else {
            Issue.record("Expected .codeBlock"); return
        }
        #expect(cb.lines == ["a", "b"])
        #expect(cb.language == "swift")
    }

    @Test("thematicBreak → .thematicBreak")
    func thematicBreak() {
        let blocks = map([.thematicBreak])
        guard case .thematicBreak(_) = blocks.first else {
            Issue.record("Expected .thematicBreak"); return
        }
    }

    @Test("table alignment mapping: .left→.leading, .center→.center, .right→.trailing")
    func tableAlignments() {
        let tbl = MarkdownTable(
            alignments: [.left, .center, .right],
            header: [[.text("A")], [.text("B")], [.text("C")]],
            rows: []
        )
        let blocks = map([.table(tbl)])
        guard case .table(let t) = blocks.first else {
            Issue.record("Expected .table"); return
        }
        #expect(t.alignments == [.leading, .center, .trailing])
        #expect(t.header.count == 3)
        // Each header cell has exactly one .text run
        for cell in t.header {
            guard case .text(_, _) = cell.first else {
                Issue.record("Expected .text in header cell"); return
            }
        }
    }

    @Test("table .none alignment → .leading")
    func tableAlignmentNone() {
        let tbl = MarkdownTable(
            alignments: [.none],
            header: [[.text("X")]],
            rows: []
        )
        let blocks = map([.table(tbl)])
        guard case .table(let t) = blocks.first else {
            Issue.record("Expected .table"); return
        }
        #expect(t.alignments == [.leading])
    }
}
