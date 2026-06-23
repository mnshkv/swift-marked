import CoreGraphics

public extension TextDocument {
    /// A small showcase document exercising headings, bold/italic/code/link
    /// inline styling, a thematic break, a bullet list, a block quote, and a
    /// code block. Reusable in SwiftUI previews, demos, and tests. The engine is
    /// style-agnostic, so this supplies concrete resolved fonts/colors.
    static var preview: TextDocument {
        let ink = CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1)
        let link = CGColor(red: 0.0, green: 0.45, blue: 0.95, alpha: 1)
        let codeInk = CGColor(red: 0.35, green: 0.35, blue: 0.38, alpha: 1)

        func body(_ size: CGFloat = 17, bold: Bool = false, italic: Bool = false,
                  mono: Bool = false, color: CGColor = ink) -> TextStyle {
            TextStyle(fontSize: size, isBold: bold, isItalic: italic, isMonospace: mono, color: color)
        }

        let heading = Paragraph(
            runs: [.text("Markdown Text Engine", body(28, bold: true))],
            style: ParagraphStyle(spacingBefore: 0, spacingAfter: 12)
        )

        let intro = Paragraph(runs: [
            .text("A read-only ", body()),
            .text("CoreText", body(bold: true)),
            .text(" typesetter with ", body()),
            .text("document-wide", body(italic: true)),
            .text(" selection, inline ", body()),
            .text("code spans", body(mono: true, color: codeInk)),
            .text(", and ", body()),
            .link(runs: [.text("links", body(color: link))], payload: LinkPayload("https://swift.org")),
            .text(".", body()),
        ], style: .body)

        let bullets = List(marker: .bullet, isTight: true, items: [
            TextDocument(blocks: [.paragraph(Paragraph(runs: [.text("Lists, quotes, tables, code blocks", body())], style: .body))]),
            TextDocument(blocks: [.paragraph(Paragraph(runs: [.text("Block and inline images", body())], style: .body))]),
        ])

        let quote = TextDocument(blocks: [.paragraph(Paragraph(
            runs: [.text("Everything is drawn in one unified layout, so a selection is continuous across the whole document.", body(italic: true))],
            style: .body
        ))])

        let code = CodeBlock(
            lines: ["let doc = MarkdownParser.parse(source)", "MarkdownTextView(textDocument)"],
            language: "swift",
            style: body(14, mono: true, color: codeInk)
        )

        return TextDocument(blocks: [
            .paragraph(heading),
            .paragraph(intro),
            .thematicBreak(RuleStyle(color: CGColor(red: 0.8, green: 0.8, blue: 0.82, alpha: 1))),
            .list(bullets),
            .quote(quote),
            .codeBlock(code),
        ])
    }
}
