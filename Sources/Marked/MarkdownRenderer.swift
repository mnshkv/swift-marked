import Foundation
import CoreGraphics

/// Maps a `MarkdownDocument` (AST) to a `TextDocument` (text engine). Filled in Wave 1.
public enum MarkdownRenderer {}

// MARK: - Task 5.1: top-level render + footnotes

public extension MarkdownRenderer {

    /// Renders a `MarkdownDocument` AST into a `TextDocument` using the given style and color scheme.
    /// Always returns a valid document; never throws or crashes, including on duplicate footnote ids.
    static func render(
        _ document: MarkdownDocument,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light
    ) -> TextDocument {
        // Build footnote number map safely — duplicate ids overwrite (last-wins), no crash.
        var footnoteNumbers: [String: Int] = [:]
        for (i, fn) in document.footnotes.enumerated() {
            footnoteNumbers[fn.id] = i + 1
        }

        let ctx = StyleContext(style, colorScheme)
        var blocks = BlockMapper.map(document.blocks, ctx: ctx, footnotes: footnoteNumbers)

        // Append footnotes section if there are any footnotes.
        if !document.footnotes.isEmpty {
            // 1. Thematic break separator
            blocks.append(.thematicBreak(RuleStyle(color: ctx.palette.rule)))

            // 2. "Footnotes" header paragraph (bold footnote style)
            var boldFootnote = ctx.footnote
            boldFootnote.isBold = true
            blocks.append(.paragraph(Paragraph(
                runs: [.text("Footnotes", boldFootnote)],
                style: ctx.bodyParagraph
            )))

            // 3. Per-footnote: numbered label paragraph + indented content blocks
            for (i, fn) in document.footnotes.enumerated() {
                let n = i + 1

                // "n. " label paragraph
                blocks.append(.paragraph(Paragraph(
                    runs: [.text("\(n). ", ctx.footnote)],
                    style: ctx.bodyParagraph
                )))

                // Footnote body blocks, each indented by definitionIndent
                let fnBlocks = BlockMapper.map(fn.blocks, ctx: ctx, footnotes: footnoteNumbers)
                for block in fnBlocks {
                    blocks.append(indentBlock(block, by: style.spacing.definitionIndent))
                }
            }
        }

        return TextDocument(blocks: blocks)
    }

    /// Parses `markdown` and renders it using the given style and color scheme.
    static func render(
        _ markdown: String,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light
    ) -> TextDocument {
        render(MarkdownParser.parse(markdown), style: style, colorScheme: colorScheme)
    }
}

// MARK: - Private helpers

private func indentBlock(_ block: Block, by amount: CGFloat) -> Block {
    guard case .paragraph(var p) = block else { return block }
    p.style.leadingIndent += amount
    return .paragraph(p)
}
