# Spec 1 — Markdown Parser → AST

**Date:** 2026-06-22
**Status:** Approved (design), pending implementation plan
**Module:** `MarkdownAST` (pure Swift, zero dependencies, no SwiftUI)

## Context

We are building a SwiftUI Markdown library following markdownguide.org
(Basic + full Extended syntax ≈ CommonMark + GFM + extended). The project is
decomposed into three independent specs, built strictly in dependency order:

1. **Spec 1 — Parser → AST** (this document). Markdown text → block/inline tree.
2. **Spec 2 — Text engine (typesetter).** Styled runs → line layout + drawing +
   selection/hit-testing (custom CoreText/TextKit engine, the C2 approach).
   Knows nothing about Markdown.
3. **Spec 3 — Markdown renderer.** Binds AST + engine: block views
   (`Grid` tables, code blocks with copy button, `AsyncImage`), a single
   configuration object passed into a factory, link handling / openURL.

Hard constraint (standing user rule): the parser is hand-written, TDD, with
**zero dependencies** — never swift-markdown or any external parser.

Target: iOS 26+ and multiplatform (macOS etc.); the parser module itself is
platform-agnostic pure Swift.

## Scope

In scope: CommonMark + GFM + extended — ATX/setext headings, paragraphs,
fenced/indented code, block quotes (nested), ordered/unordered/task lists
(nested, tight/loose, lazy continuation), thematic breaks, emphasis/strong,
inline code, links/images (inline + reference), CommonMark autolinks,
GFM extended autolinks (bare `www.`/`http(s)://`/email), strikethrough,
hard/soft breaks, backslash escapes, GFM tables, footnotes, definition lists.
Code block language captured as info string only (highlighting is Spec 3).

Out of scope (documented limitations, passed through as literal text):
HTML blocks and inline HTML; character/entity references (`&amp;`, `&#42;`);
rare CommonMark corners (nested links, info strings containing backticks, etc.).

## Section 1 — Module boundary & public API

Separate target `MarkdownAST`, pure Swift, no `import SwiftUI`, no deps. Single
entry point:

```swift
public enum MarkdownParser {
    public static func parse(_ source: String) -> MarkdownDocument
}
```

- Parsing is total: any input yields a valid `MarkdownDocument` (Markdown has no
  syntax errors — unrecognized input becomes text). No `throws`.
- All AST types are `public`, `Sendable`, `Equatable`, `Hashable`. `Equatable`
  is required for TDD (compare expected tree). Value types only, no classes.
- **No source ranges** in nodes (YAGNI). Rendering + selection operate over
  rendered text, not source offsets. Can be added later if a source-mapped
  editor is ever needed.

## Section 2 — AST model

```swift
public struct MarkdownDocument: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var footnotes: [FootnoteDefinition]   // collected globally, rendered at end
}

public indirect enum MarkdownBlock: Equatable, Sendable, Hashable {
    case heading(level: Int, content: [MarkdownInline])
    case paragraph(content: [MarkdownInline])
    case blockQuote(blocks: [MarkdownBlock])
    case list(MarkdownList)
    case codeBlock(language: String?, code: String)   // language = info string
    case thematicBreak
    case table(MarkdownTable)
    case definitionList([MarkdownDefinition])
}

public struct MarkdownList: Equatable, Sendable, Hashable {
    public enum Kind: Equatable, Sendable, Hashable { case bullet; case ordered(start: Int) }
    public var kind: Kind
    public var isTight: Bool                 // tight/loose → render spacing
    public var items: [MarkdownListItem]
}

public struct MarkdownListItem: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]       // item contains blocks (nested lists, paragraphs)
    public var task: TaskState?              // nil = normal; checked/unchecked = GFM task item
}

public enum TaskState: Equatable, Sendable, Hashable { case checked, unchecked }

public struct MarkdownTable: Equatable, Sendable, Hashable {
    public enum Alignment: Equatable, Sendable, Hashable { case none, left, center, right }
    public var alignments: [Alignment]
    public var header: [[MarkdownInline]]    // cells = arrays of inlines
    public var rows: [[[MarkdownInline]]]
}

public struct MarkdownDefinition: Equatable, Sendable, Hashable {
    public var term: [MarkdownInline]
    public var details: [[MarkdownBlock]]
}

public struct FootnoteDefinition: Equatable, Sendable, Hashable {
    public var id: String
    public var blocks: [MarkdownBlock]
}

public indirect enum MarkdownInline: Equatable, Sendable, Hashable {
    case text(String)
    case emphasis([MarkdownInline])
    case strong([MarkdownInline])
    case strikethrough([MarkdownInline])
    case code(String)
    case link(destination: String, title: String?, content: [MarkdownInline])
    case image(source: String, title: String?, alt: String)
    case autolink(url: String)
    case footnoteReference(id: String)
    case softBreak
    case hardBreak
}
```

Key model decisions:
1. Footnote definitions live in `document.footnotes`; text carries only
   `.footnoteReference(id:)`. Renderer assembles the footnote section at the end.
2. No source ranges (see Section 1).
3. HTML out of scope — raw HTML flows through as literal text.

## Section 3 — Block parsing

Line-oriented scanner on the CommonMark container/leaf model, in **two passes**.

**Pass A — block structure.** Walk lines, maintaining a stack of open
*containers*:
- **Containers** (`blockQuote`, list items): match each line's prefix against
  open containers (`>` marker, list marker, indentation), then recursively parse
  contained blocks. Handles lazy continuation and tight/loose (blank lines
  between items).
- **Leaf blocks** dispatched from the current line after stripping container
  prefixes: ATX heading (`#…`), setext (underline `===`/`---` with lookback to a
  preceding paragraph), fenced code (```` ``` ````/`~~~` + info string), indented
  code (4 spaces), thematic break (`---`/`***`/`___`), table (header + delimiter
  row `|---|`), otherwise paragraph (accumulate until blank line or an
  interrupting construct).
- Simultaneously collect into tables: **link reference definitions**
  `[label]: url "title"` and **footnote definitions** `[^id]: …`. This is why a
  second pass exists — a reference may be defined later in the document.

**Pass B — inline.** For each leaf block, parse its raw text into
`[MarkdownInline]` using the link/footnote tables from Pass A.

## Section 4 — Inline parsing (two phases, CommonMark)

1. **Tokenization.** Left to right: backslash escapes, code spans (` `` `, by
   backtick count), `<autolinks>`, `[`/`]`/`(` markers for links/images,
   delimiter runs `*` / `_` / `~~` with left/right-flanking classification,
   hard break (two trailing spaces or `\` before newline).
2. **Delimiter resolution.** CommonMark delimiter stack: emphasis/strong with
   flanking rules and the "rule of 3"; strikethrough `~~`. Links/images via
   bracket matching with link precedence, processed inside-out; reference links
   resolved against the Pass A table.

## Section 5 — Extended features

- **Tables (GFM):** header row, delimiter row with alignment (`:--`, `:-:`,
  `--:`), then data rows; cell counts normalized to the header (extra dropped,
  missing filled empty).
- **Task lists (GFM):** list item starting with `[ ]`/`[x]` → `MarkdownListItem.task`.
- **Footnotes:** `[^id]` in text → `.footnoteReference`; `[^id]: …` (incl.
  multi-line indented) → `document.footnotes`.
- **Definition lists (extended):** `Term` line followed by `: description` lines.
- **Syntax highlighting:** parser only stores info-string language in
  `codeBlock.language`; highlighting happens in Spec 3.
- **Autolinks:** CommonMark `<https://…>` yes; GFM extended bare autolinks
  (`www.…`, `http(s)://…` without brackets, email) **included**.

## Section 6 — Testing

- **TDD on Swift Testing** (`@Test`/`#expect`), target `MarkdownASTTests`. Every
  feature/bug starts as a failing test.
- **Conformance suite:** in addition to hand-written TDD tests, add the official
  CommonMark `spec.json` and GFM spec fixtures as test resource data files and
  run them via a parameterized test. These are reference cases, not a code
  dependency (the "own parser" rule is intact). Cases that exercise our
  deliberate limitations are marked as known-skips with a reason.

## Section 7 — Out of scope / known limitations

HTML (blocks and inline), character/entity references, nested links, and other
rare CommonMark corners are documented in the `MarkdownParser` doc comment.

## Success criteria

- `MarkdownParser.parse` produces correct `MarkdownDocument` for all in-scope
  constructs, validated by TDD tests.
- CommonMark/GFM conformance fixtures pass except documented known-skips.
- `swift build`, `swift test`, and SwiftLint all green.
- Zero external dependencies; no SwiftUI import in `MarkdownAST`.
