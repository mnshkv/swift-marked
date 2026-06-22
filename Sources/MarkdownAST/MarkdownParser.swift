/// Parses Markdown (CommonMark 0.31 + GFM + extended) into a value-type AST.
///
/// Supported: ATX/setext headings, paragraphs, fenced/indented code, block quotes (nested),
/// ordered/unordered/task lists (nested, tight/loose, lazy continuation), thematic breaks,
/// emphasis/strong, inline code, links/images (inline + reference), CommonMark autolinks,
/// GFM extended autolinks, strikethrough, hard/soft breaks, backslash escapes, GFM tables,
/// footnotes, definition lists. Code-block language is the info string only.
///
/// Out of scope (passed through as literal text): HTML blocks and inline HTML, character/entity
/// references, nested links, info strings containing backticks, and other rare CommonMark corners.
public enum MarkdownParser {
    private static let maxDepth = 512

    /// Parses `source` into a `MarkdownDocument`. Pass A scans blocks and
    /// collects definitions; Pass B resolves every raw leaf into inline nodes
    /// once `defs` is complete, so forward references (defined after use) work.
    public static func parse(_ source: String) -> MarkdownDocument {
        let lines = splitIntoLines(source).map { expandTabs($0) }
        let defs = DefinitionStore()
        let rawBlocks = BlockParser(defs: defs).parse(lines, depth: 0)
        let blocks = resolveInlines(rawBlocks, defs: defs, depth: 0)
        let footnotes = defs.pendingFootnotes.map { footnote -> FootnoteDefinition in
            let rawBody = BlockParser(defs: defs).parse(footnote.bodyLines, depth: 0)
            return FootnoteDefinition(id: footnote.id, blocks: resolveInlines(rawBody, defs: defs, depth: 0))
        }
        return MarkdownDocument(blocks: blocks, footnotes: footnotes)
    }

    /// Pass B: recursively resolve a `[RawBlock]` tree into `[MarkdownBlock]`,
    /// inline-parsing every leaf string against the now-complete `defs`.
    static func resolveInlines(_ raw: [RawBlock], defs: DefinitionStore, depth: Int) -> [MarkdownBlock] {
        guard depth < maxDepth else { return [] } // recursion-depth fallback
        let inline = InlineParser(defs: defs)
        return raw.map { resolveBlock($0, inline: inline, defs: defs, depth: depth) }
    }

    private static func resolveBlock(_ block: RawBlock, inline: InlineParser, defs: DefinitionStore, depth: Int) -> MarkdownBlock {
        switch block {
        case .paragraph(let raw):
            return .paragraph(content: inline.parse(raw, depth: depth))
        case .heading(let level, let raw):
            return .heading(level: level, content: inline.parse(raw, depth: depth))
        case .thematicBreak:
            return .thematicBreak
        case .codeBlock(let language, let code):
            return .codeBlock(language: language, code: code)
        case .blockQuote(let blocks):
            return .blockQuote(blocks: resolveInlines(blocks, defs: defs, depth: depth + 1))
        case .list(let list):
            let items = list.items.map {
                MarkdownListItem(blocks: resolveInlines($0.blocks, defs: defs, depth: depth + 1), task: $0.task)
            }
            return .list(MarkdownList(kind: list.kind, isTight: list.isTight, items: items))
        case .table(let table):
            let header = (table.header.first ?? []).map { inline.parse($0, depth: depth) }
            let rows = table.rows.map { row in row.map { inline.parse($0, depth: depth) } }
            return .table(MarkdownTable(alignments: table.alignments, header: header, rows: rows))
        case .definitionList(let definitions):
            let resolved = definitions.map { definition in
                MarkdownDefinition(
                    term: inline.parse(definition.term, depth: depth),
                    details: definition.details.map { resolveInlines($0, defs: defs, depth: depth + 1) }
                )
            }
            return .definitionList(resolved)
        }
    }
}
public struct MarkdownDocument: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var footnotes: [FootnoteDefinition]
    /// Creates a document from its top-level blocks and footnote definitions.
    public init(blocks: [MarkdownBlock], footnotes: [FootnoteDefinition]) { self.blocks = blocks; self.footnotes = footnotes }
}
