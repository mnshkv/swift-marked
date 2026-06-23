import CoreGraphics

public extension TextDocument {
    /// A comprehensive showcase document exercising **every** content type the
    /// engine supports — headings, all inline styles (bold/italic/bold-italic/
    /// strikethrough/monospace/link), hard line breaks, inline & block images,
    /// nested unordered lists, ordered lists, block quotes, GFM tables with
    /// column alignment, code blocks, and thematic breaks. Each feature is
    /// preceded by a small label so you can see, at a glance, what renders and
    /// what does not. Reusable in SwiftUI previews, demos, and tests.
    static var preview: TextDocument {
        let ink = CGColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)
        let muted = CGColor(red: 0.45, green: 0.45, blue: 0.5, alpha: 1)
        let link = CGColor(red: 0.0, green: 0.45, blue: 0.95, alpha: 1)
        let codeInk = CGColor(red: 0.30, green: 0.32, blue: 0.40, alpha: 1)
        let rule = CGColor(red: 0.80, green: 0.80, blue: 0.83, alpha: 1)

        func style(_ size: CGFloat = 16, bold: Bool = false, italic: Bool = false,
                   strike: Bool = false, mono: Bool = false, color: CGColor = ink) -> TextStyle {
            TextStyle(fontSize: size, isBold: bold, isItalic: italic,
                      isStrikethrough: strike, isMonospace: mono, color: color)
        }
        func txt(_ string: String, _ s: TextStyle) -> InlineRun { .text(string, s) }
        func para(_ runs: [InlineRun], spacingAfter: CGFloat = 8) -> Block {
            .paragraph(Paragraph(runs: runs, style: ParagraphStyle(spacingAfter: spacingAfter)))
        }
        // A small grey section label so each feature below is identifiable.
        func label(_ string: String) -> Block {
            .paragraph(Paragraph(runs: [txt(string.uppercased(), style(11, bold: true, color: muted))],
                                 style: ParagraphStyle(spacingBefore: 6, spacingAfter: 2)))
        }
        func divider() -> Block { .thematicBreak(RuleStyle(color: rule)) }
        func textDoc(_ string: String) -> TextDocument {
            TextDocument(blocks: [para([txt(string, style())], spacingAfter: 2)])
        }

        var blocks: [Block] = []

        // Title
        blocks.append(para([txt("Engine Feature Showcase", style(28, bold: true))], spacingAfter: 4))
        blocks.append(para([txt("Every content type the engine can render.", style(14, italic: true, color: muted))]))
        blocks.append(divider())

        // Headings (font-size driven)
        blocks.append(label("Headings"))
        blocks.append(para([txt("Heading 1", style(26, bold: true))], spacingAfter: 2))
        blocks.append(para([txt("Heading 2", style(21, bold: true))], spacingAfter: 2))
        blocks.append(para([txt("Heading 3", style(17, bold: true))]))

        // Inline styles
        blocks.append(label("Inline styles"))
        blocks.append(para([
            txt("Plain, ", style()),
            txt("bold", style(bold: true)),
            txt(", ", style()),
            txt("italic", style(italic: true)),
            txt(", ", style()),
            txt("bold italic", style(bold: true, italic: true)),
            txt(", ", style()),
            txt("strikethrough", style(strike: true)),
            txt(", ", style()),
            txt("monospace", style(mono: true, color: codeInk)),
            txt(", and ", style()),
            .link(runs: [txt("a link", style(color: link))], payload: LinkPayload("https://swift.org")),
            txt(".", style()),
        ]))

        // Hard line break
        blocks.append(label("Hard line break"))
        blocks.append(para([
            txt("First line, then a hard break", style()),
            .lineBreak(hard: true),
            txt("second line on its own.", style()),
        ]))

        // Inline image
        blocks.append(label("Inline image"))
        blocks.append(para([
            txt("An inline image ", style()),
            .inlineImage(ImageAttachment(source: "inline", intrinsicSize: CGSize(width: 20, height: 20), alt: "icon")),
            txt(" sits in the text flow.", style()),
        ]))

        // Unordered list with nesting
        blocks.append(label("Unordered list (nested)"))
        let nested = List(marker: .bullet, isTight: true, items: [
            textDoc("Nested item A"),
            textDoc("Nested item B"),
        ])
        blocks.append(.list(List(marker: .bullet, isTight: true, items: [
            textDoc("First bullet"),
            TextDocument(blocks: [para([txt("Second bullet, with a sub-list:", style())], spacingAfter: 2), .list(nested)]),
            textDoc("Third bullet"),
        ])))

        // Ordered list
        blocks.append(label("Ordered list"))
        blocks.append(.list(List(marker: .ordered(start: 1), isTight: true, items: [
            textDoc("Step one"),
            textDoc("Step two"),
            textDoc("Step three"),
        ])))

        // Block quote
        blocks.append(label("Block quote"))
        blocks.append(.quote(TextDocument(blocks: [
            para([txt("A block quote — drawn with a left bar.", style())], spacingAfter: 4),
            para([txt("Second paragraph inside the same quote.", style(italic: true))], spacingAfter: 0),
        ])))

        // GFM table with alignments
        blocks.append(label("Table (column alignment)"))
        let cell = style(15)
        let head = style(15, bold: true)
        blocks.append(.table(Table(
            alignments: [.leading, .center, .trailing],
            header: [[txt("Component", head)], [txt("Status", head)], [txt("Tests", head)]],
            rows: [
                [[txt("Parser", cell)], [txt("Done", cell)], [txt("299", cell)]],
                [[txt("Text engine", cell)], [txt("Done", cell)], [txt("171", cell)]],
                [[txt("Renderer", cell)], [txt("Next", cell)], [txt("0", cell)]],
            ],
            cellStyle: cell
        )))

        // Code block
        blocks.append(label("Code block"))
        blocks.append(.codeBlock(CodeBlock(
            lines: [
                "let doc = MarkdownParser.parse(source)",
                "let textDoc = render(doc)        // Spec 3 (next)",
                "MarkdownTextView(textDoc)",
            ],
            language: "swift",
            style: style(13, mono: true, color: codeInk)
        )))

        // Block image
        blocks.append(label("Block image"))
        blocks.append(.image(ImageAttachment(source: "block",
                                             intrinsicSize: CGSize(width: 320, height: 140),
                                             alt: "A sample block image")))

        // Thematic break
        blocks.append(label("Thematic break"))
        blocks.append(divider())

        return TextDocument(blocks: blocks)
    }
}
