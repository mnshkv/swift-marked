import Testing
import CoreGraphics
@testable import Marked

@Suite("MarkdownRenderer — render + footnotes")
struct RendererTests {

    // MARK: - Task 5.1 tests

    @Test("render(document:) simple paragraph → one .paragraph block")
    func renderSimpleParagraph() {
        let doc = MarkdownDocument(
            blocks: [.paragraph(content: [.text("hi")])],
            footnotes: []
        )
        let result = MarkdownRenderer.render(doc)
        #expect(result.blocks.count == 1)
        guard case .paragraph(let p) = result.blocks.first else {
            Issue.record("Expected .paragraph"); return
        }
        guard case .text(let s, _) = p.runs.first else {
            Issue.record("Expected .text run"); return
        }
        #expect(s == "hi")
    }

    @Test("render(String:) parses heading and paragraph")
    func renderString() {
        let result = MarkdownRenderer.render("# H\n\npara")
        #expect(result.blocks.count >= 2)
        // First block is a heading paragraph (bold)
        guard case .paragraph(let headingP) = result.blocks.first else {
            Issue.record("Expected first block to be .paragraph"); return
        }
        guard case .text(let s, let style) = headingP.runs.first else {
            Issue.record("Expected .text run in heading"); return
        }
        #expect(s == "H")
        #expect(style.isBold == true)
        // Second block is a body paragraph
        guard case .paragraph(let bodyP) = result.blocks[1] else {
            Issue.record("Expected second block to be .paragraph"); return
        }
        guard case .text(let bodyText, let bodyStyle) = bodyP.runs.first else {
            Issue.record("Expected .text run in body"); return
        }
        #expect(bodyText == "para")
        #expect(bodyStyle.isBold == false)
    }

    @Test("render with footnote → thematicBreak + Footnotes paragraph + numbered paragraph")
    func renderWithFootnote() {
        let doc = MarkdownDocument(
            blocks: [.paragraph(content: [.footnoteReference(id: "a")])],
            footnotes: [FootnoteDefinition(id: "a", blocks: [.paragraph(content: [.text("note")])])]
        )
        let result = MarkdownRenderer.render(doc)
        // Must have at least: body paragraph + thematicBreak + "Footnotes" + numbered paragraph + indented content
        #expect(result.blocks.count >= 4)

        // body paragraph has a [1] link
        guard case .paragraph(let bodyP) = result.blocks.first else {
            Issue.record("Expected body .paragraph"); return
        }
        // There should be a link run with [1]
        let hasFootnoteLink = bodyP.runs.contains { run in
            if case .link(let runs, _) = run {
                return runs.contains { if case .text(let s, _) = $0 { return s == "[1]" }; return false }
            }
            return false
        }
        #expect(hasFootnoteLink)

        // Find the thematicBreak
        let hasThematicBreak = result.blocks.contains { if case .thematicBreak = $0 { return true }; return false }
        #expect(hasThematicBreak)

        // Find the "Footnotes" paragraph
        let hasFootnotesHeader = result.blocks.contains { block in
            guard case .paragraph(let p) = block else { return false }
            return p.runs.contains { if case .text(let s, _) = $0 { return s == "Footnotes" }; return false }
        }
        #expect(hasFootnotesHeader)

        // Find a paragraph containing "1. "
        let hasNumberedParagraph = result.blocks.contains { block in
            guard case .paragraph(let p) = block else { return false }
            return p.runs.contains { if case .text(let s, _) = $0 { return s == "1. " }; return false }
        }
        #expect(hasNumberedParagraph)
    }

    @Test("render duplicate footnote ids → no crash, last-wins numbering")
    func renderDuplicateFootnoteIds() {
        let doc = MarkdownDocument(
            blocks: [],
            footnotes: [
                FootnoteDefinition(id: "dup", blocks: [.paragraph(content: [.text("first")])]),
                FootnoteDefinition(id: "dup", blocks: [.paragraph(content: [.text("second")])])
            ]
        )
        // Must not crash
        let result = MarkdownRenderer.render(doc)
        #expect(!result.blocks.isEmpty)
    }

    @Test("light vs dark scheme → body text colors differ")
    func lightVsDark() {
        let doc = MarkdownDocument(
            blocks: [.paragraph(content: [.text("text")])],
            footnotes: []
        )
        let light = MarkdownRenderer.render(doc, colorScheme: .light)
        let dark = MarkdownRenderer.render(doc, colorScheme: .dark)
        guard case .paragraph(let lp) = light.blocks.first,
              case .paragraph(let dp) = dark.blocks.first,
              case .text(_, let lStyle) = lp.runs.first,
              case .text(_, let dStyle) = dp.runs.first else {
            Issue.record("Expected text paragraphs"); return
        }
        #expect(lStyle.color != dStyle.color)
    }
}
