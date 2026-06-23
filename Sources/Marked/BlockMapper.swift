import CoreGraphics

enum BlockMapper {

    static func map(
        _ mdBlocks: [MarkdownBlock],
        ctx: StyleContext,
        footnotes: [String: Int]
    ) -> [Block] {
        var blocks: [Block] = []
        for block in mdBlocks {
            switch block {
            case .heading(let level, let content):
                blocks.append(.paragraph(Paragraph(
                    runs: InlineMapper.map(content, base: ctx.heading(level), ctx: ctx, footnotes: footnotes),
                    style: ctx.headingParagraph()
                )))
            case .paragraph(let content):
                blocks.append(.paragraph(Paragraph(
                    runs: InlineMapper.map(content, base: ctx.body, ctx: ctx, footnotes: footnotes),
                    style: ctx.bodyParagraph
                )))
            case .blockQuote(let inner):
                blocks.append(.quote(TextDocument(blocks: map(inner, ctx: ctx, footnotes: footnotes))))
            case .codeBlock(let lang, let code):
                blocks.append(.codeBlock(CodeBlock(
                    lines: code.split(separator: "\n", omittingEmptySubsequences: false).map(String.init),
                    language: lang,
                    style: ctx.codeBlock
                )))
            case .thematicBreak:
                blocks.append(.thematicBreak(RuleStyle(color: ctx.palette.rule)))
            case .table(let t):
                let alignments = t.alignments.map(mapAlignment)
                let header = t.header.map { cell in
                    InlineMapper.map(cell, base: ctx.body, ctx: ctx, footnotes: footnotes)
                }
                let rows = t.rows.map { row in
                    row.map { cell in
                        InlineMapper.map(cell, base: ctx.body, ctx: ctx, footnotes: footnotes)
                    }
                }
                blocks.append(.table(Table(
                    alignments: alignments,
                    header: header,
                    rows: rows,
                    cellStyle: ctx.body
                )))
            case .list(let list):
                let marker: ListMarkerStyle = {
                    switch list.kind {
                    case .bullet: return .bullet
                    case .ordered(let s): return .ordered(start: s)
                    }
                }()
                let items = list.items.map { item in
                    TextDocument(blocks: map(item.blocks, ctx: ctx, footnotes: footnotes))
                }
                blocks.append(.list(List(marker: marker, isTight: list.isTight, items: items)))
            default:
                break
            }
        }
        return blocks
    }

    // MARK: - Private helpers

    private static func mapAlignment(_ alignment: MarkdownTable.Alignment) -> TextAlignment {
        switch alignment {
        case .none, .left: return .leading
        case .center: return .center
        case .right: return .trailing
        }
    }
}
