# Markdown Parser Implementation Plan — v2

> **Supersedes** `2026-06-22-markdown-parser.md` (v1). v1 was reviewed twice (adversarial 8-lens review +
> a 9-lens deep review, 134 agents, 113 confirmed findings). **v1 was never revised** — 0 of 21 prior
> findings were fixed. v2 incorporates all 9 critical fixes (K1–K10), all major fixes, and decomposes the
> work into ~50 micro-tasks across 12 waves so many small agents can work in parallel. See
> `reviews/2026-06-22-parser-deep-review.md` for the evidence base (every fix below is cited there with
> file:line + CommonMark rule).
>
> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development` or
> `superpowers:executing-plans`. Each micro-task is atomic: failing test → implement → green → commit.
> Respect `blockedBy`; never start a micro-task whose blockers aren't merged.

**Goal:** Hand-written, zero-dependency Markdown parser: text → value-type AST covering CommonMark 0.31
+ GFM + extended.

**Architecture (real two-pass):**
- **Pass A — block structure.** `BlockParser` walks lines, builds an *internal* `RawBlock` tree whose
  leaves hold **raw `String` text** (not yet inlined), and registers link-reference / footnote
  definitions into a shared `DefinitionStore`. Containers (blockquote/list) strip their prefixes and
  recurse, producing nested `RawBlock`s.
- **Pass B — inline resolution.** After Pass A completes and `DefinitionStore` is fully populated, a
  recursive walk converts every `RawBlock` leaf (paragraph, heading, table cells, definition terms,
  footnote bodies) into `[MarkdownInline]` via `InlineParser(defs:).parse(raw)`. This is what makes
  forward references work (K1).

No SwiftUI, no `throws` — parsing is total. Swift 6.2, SwiftPM, Swift Testing (`@Test`/`#expect`).

## Global Constraints

- Module name: `MarkdownAST`. No `import SwiftUI`, **no external dependencies** anywhere.
- Swift tools version: 6.2 (already in `Package.swift`).
- Public AST types: `public`, `Sendable`, `Equatable`, `Hashable`, **value types only**.
- **Exception (internal only):** `DefinitionStore` is a `final class` so recursive `BlockParser` calls
  share one mutable definition table. It is `internal`, never exposed in the public AST, so the
  public-API "value types only" constraint is intact (review F9-MINOR resolved by scoping).
- `MarkdownParser.parse` never throws, never fails — any `String` yields a valid `MarkdownDocument`.
- TDD only: every behavior starts as a failing Swift Testing test. Commit after each micro-task.
- No source ranges in AST nodes (YAGNI). HTML blocks/inline and character/entity references are out of
  scope (pass through as literal text).
- Test framework is Swift Testing, NOT XCTest. Use `#expect(...)`, not `XCTAssert`.
- Run build with `swift build`, tests with `swift test`.
- **Hard recursion guard:** every recursive descent (block-quote, list, inline link text, emphasis
  nesting) carries a `depth` counter; abort to a literal/text node past a fixed ceiling (default 512)
  to avoid stack overflow on pathological input (review minor).
- **Line endings & tabs:** `splitIntoLines` normalizes `\n`/`\r\n`/`\r`; `expandTabs` expands tabs to
  4-column stops **before** any indentation measurement (fix F1/M2).

## Open questions (decisions applied in v2 — revisit with user before the affected waves)

- **OQ1 — Conformance methodology (Wave 11):** v2 implements the **AST→HTML renderer** approach
  (`astToHTML` + `normalizeHTML`) for real CommonMark/GFM conformance numbers. Cost: a correct
  test-only HTML renderer. *Alternative:* curated hand-authored AST expectations (lighter, less
  exhaustive). Flagged at W11-T26d.
- **OQ2 — Extended depth:** v2 **implements now** multi-paragraph footnote bodies (M13), multi-line
  link-reference definitions (M11), and multi-block definition-list details (M5). *Alternative:*
  document as v1 limitations.
- **OQ3 — Definition-list `details` cardinality:** v2 keeps `details: [[MarkdownBlock]]` (multiple
  definitions per term) — review-recommended.

## File map (target layout after all waves)

```
Sources/MarkdownAST/
  MarkdownParser.swift      public enum + parse pipeline + RawBlock→MarkdownBlock resolver (Pass B)
  MarkdownBlock.swift       public block/list/table/definition/footnote model
  MarkdownInline.swift      public inline model
  Line.swift                splitIntoLines, expandTabs
  RawBlock.swift            internal RawBlock tree (Pass A output)
  BlockParser.swift         Pass A: lines → [RawBlock], leaf/container dispatch
  Containers.swift          stripUpTo3Spaces, isBlockStart, canInterruptParagraph, blockquote strip
  ListParser.swift          listMarker, parseList
  TableParser.swift         splitTableRow, delimiterAlignments
  DefinitionStore.swift     DefinitionStore + linkReferenceDefinition + footnoteDefinition
  InlineParser.swift        Pass B: raw String → [MarkdownInline] (tokenizer)
  EmphasisResolver.swift    InlineToken, classifyFlanking, processEmphasis, coalesceText
  LinkParser.swift          parseInlineLinkOrImage, matchBracket, matchParen, splitDestinationAndTitle
  Autolink.swift            isURIAutolink, isEmailAutolink, GFM extended bare autolinks
Tests/MarkdownASTTests/
  ...per-feature test files...
  Resources/commonmark-spec.json, gfm-spec.json
  ConformanceHTML.swift, ConformanceTests.swift, KnownSkips.swift
```

## Dependency spine (strictly sequential)

`W0 → W2-T4 → W6-T16 → W6-T17 → W7-T18a → W8-T18c → (W9-T18d | W9-T20c | W9-T22)`

Everything else fans out. Each wave lists its micro-tasks with `blockedBy`.

---

## Wave 0 — foundation (one agent, one green commit)

### Task 1: W0-T1 — Module scaffold + full AST model + smoke tests

**Files:** Modify `Package.swift`; Create `Sources/MarkdownAST/{MarkdownParser.swift,MarkdownBlock.swift,MarkdownInline.swift}`; Create `Tests/MarkdownASTTests/{SmokeTests.swift,ModelTests.swift}`; `git rm` the old template `Sources/swiftui-markdown/*`, `Tests/swiftui-markdownTests/*`.

**Interfaces:** `enum MarkdownParser { public static func parse(_:) -> MarkdownDocument }`; full public model (all types from spec §2) — merges v1 Tasks 1+2 so the module compiles standalone (fix K10).

- [ ] **Step 1: `Package.swift`**

```swift
// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "swiftui-markdown",
    products: [.library(name: "MarkdownAST", targets: ["MarkdownAST"])],
    targets: [
        .target(name: "MarkdownAST"),
        .testTarget(name: "MarkdownASTTests", dependencies: ["MarkdownAST"]),
    ]
)
```

- [ ] **Step 2: remove template**

```bash
git rm Sources/swiftui-markdown/swiftui_markdown.swift Tests/swiftui-markdownTests/swiftui_markdownTests.swift
rmdir Sources/swiftui-markdown Tests/swiftui-markdownTests 2>/dev/null || true
```

- [ ] **Step 3: `MarkdownBlock.swift`** — exactly the spec §2 model:

```swift
public indirect enum MarkdownBlock: Equatable, Sendable, Hashable {
    case heading(level: Int, content: [MarkdownInline])
    case paragraph(content: [MarkdownInline])
    case blockQuote(blocks: [MarkdownBlock])
    case list(MarkdownList)
    case codeBlock(language: String?, code: String)
    case thematicBreak
    case table(MarkdownTable)
    case definitionList([MarkdownDefinition])
}
public struct MarkdownList: Equatable, Sendable, Hashable {
    public enum Kind: Equatable, Sendable, Hashable { case bullet; case ordered(start: Int) }
    public var kind: Kind; public var isTight: Bool; public var items: [MarkdownListItem]
    public init(kind: Kind, isTight: Bool, items: [MarkdownListItem]) { self.kind = kind; self.isTight = isTight; self.items = items }
}
public struct MarkdownListItem: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]; public var task: TaskState?
    public init(blocks: [MarkdownBlock], task: TaskState? = nil) { self.blocks = blocks; self.task = task }
}
public enum TaskState: Equatable, Sendable, Hashable { case checked, unchecked }
public struct MarkdownTable: Equatable, Sendable, Hashable {
    public enum Alignment: Equatable, Sendable, Hashable { case none, left, center, right }
    public var alignments: [Alignment]; public var header: [[MarkdownInline]]; public var rows: [[[MarkdownInline]]]
    public init(alignments: [Alignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) { self.alignments = alignments; self.header = header; self.rows = rows }
}
public struct MarkdownDefinition: Equatable, Sendable, Hashable {
    public var term: [MarkdownInline]; public var details: [[MarkdownBlock]]
    public init(term: [MarkdownInline], details: [[MarkdownBlock]]) { self.term = term; self.details = details }
}
public struct FootnoteDefinition: Equatable, Sendable, Hashable {
    public var id: String; public var blocks: [MarkdownBlock]
    public init(id: String, blocks: [MarkdownBlock]) { self.id = id; self.blocks = blocks }
}
```

- [ ] **Step 4: `MarkdownInline.swift`** — spec §2 inline model (no `unparsed` case: raw text lives in `RawBlock`, not in `MarkdownInline`).

```swift
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

- [ ] **Step 5: `MarkdownParser.swift`** — stub `parse` returns empty doc; real pipeline lands in later waves.

```swift
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
    public static func parse(_ source: String) -> MarkdownDocument {
        MarkdownDocument(blocks: [], footnotes: [])
    }
}
public struct MarkdownDocument: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var footnotes: [FootnoteDefinition]
    public init(blocks: [MarkdownBlock], footnotes: [FootnoteDefinition]) { self.blocks = blocks; self.footnotes = footnotes }
}
```

- [ ] **Step 6: tests** — `SmokeTests.swift` (`parse("")` → empty) + `ModelTests.swift` (construct & equate block/list/table/definition/footnote). Use `#expect`.
- [ ] **Step 7: `swift test` → PASS; commit** `chore: scaffold MarkdownAST module and full value-type model`.

---

## Wave 1 — fan-out (after W0; 6 parallel agents)

### Task 2: W1-T3 — Line splitting + tab expansion
**blockedBy:** W0. **Files:** `Line.swift`, `LineTests.swift`.
**Interfaces:** `func splitIntoLines(_ source: String) -> [Substring]` (normalize `\n`/`\r\n`/`\r`, preserve mid blanks, no trailing empty); `func expandTabs(_ line: Substring, tabWidth: Int = 4) -> String` (expand to next multiple of 4; fix F1/M2).

- [ ] **Step 1 failing tests:** `splitsOnAllLineEndings` (`"a\nb\r\nc\rd"` → `["a","b","c","d"]`); `preservesBlankLinesButNotTrailingNewline` (`"a\n\nb\n"` → `["a","","b"]`); `emptyStringIsNoLines`; `tabsExpandToFourColStop` (`expandTabs("\t# H")` == `"    # H"`, `expandTabs("a\tb")` == `"a   b"`); `tabMidlineAlignsToNextMultiple` (`expandTabs("ab\tcd")` == `"ab  cd"`).
- [ ] **Step 2: Run, FAIL.**
- [ ] **Step 3: Implement** `splitIntoLines` (index walk, handle `\r\n`) and `expandTabs` (walk chars, on `\t` append spaces to next multiple of `tabWidth`).
- [ ] **Step 4: PASS. Step 5: commit** `feat: line splitting and tab expansion`.

### Task 3: W1-T14store — DefinitionStore
**blockedBy:** W0 (needs `FootnoteDefinition`). **Files:** `DefinitionStore.swift` (store only — no parsers yet), `DefinitionStoreTests.swift`.
**Interfaces:** `final class DefinitionStore` with `normalize(_:)` (trim, lowercase, collapse internal whitespace runs to single space), `addLink(label:destination:title:)` (first-def-wins), `link(for:) -> LinkDef?`, `addFootnote(_:)`, `hasFootnote(_ id:) -> Bool`, `footnotes: [FootnoteDefinition]`. `struct LinkDef { destination: String; title: String? }`.

- [ ] **Step 1 failing tests:** `normalize` (`"Foo  BAR"` → `"foo bar"`); first-def-wins (`[a]: x` then `[a]: y` → `link(for:"a").destination == "x"`); `hasFootnote` true after `addFootnote`.
- [ ] **Step 3: Implement.** `import Foundation`.
- [ ] **Step 5: commit** `feat: DefinitionStore for link reference and footnote definitions`.

### Task 4: W1-T26a — AST→HTML renderer (conformance-only)
**blockedBy:** W0. **Files:** `Tests/MarkdownASTTests/ConformanceHTML.swift`.
**Interfaces:** `func astToHTML(_ doc: MarkdownDocument) -> String` — test-only minimal renderer covering every in-scope construct. **This depends only on the AST model, not on the parser**, so it can be written and unit-tested against hand-built ASTs before the parser exists (fixes F3-swift-compile, supports OQ1).

- [ ] **Step 1 failing tests:** build ASTs by hand and assert HTML: paragraph → `<p>…</p>`; heading → `<hN>…</hN>`; emphasis → `<em>`; strong → `<strong>`; code → `<code>`; strikethrough → `<del>`; link → `<a href="…" title="…">`; image → `<img src="…" alt="…" title="…">`; autolink → `<a href="url">url</a>`; bullet list tight → `<ul><li>…</li></ul>`; ordered → `<ol start="N">`; loose → paragraphs inside `<li>`; blockquote → `<blockquote>…</blockquote>`; codeBlock → `<pre><code class="language-x">…</code></pre>` (escape HTML); thematicBreak → `<hr />`; table → `<table><thead>…</tbody>` with `<th style="text-align:…">`; definitionList → `<dl><dt>…</dt><dd>…</dd>`; softBreak → `\n`; hardBreak → `<br />`; footnoteReference → `<a href="#fn-id">…</a>`; HTML-escape text (`&`→`&amp;`, `<`→`&lt;`, `>`→`&gt;`, `"`→`&quot;`).
- [ ] **Step 3: Implement** recursive `blockHTML`/`inlineHTML`. This is the biggest single test-only unit; budget iterations.
- [ ] **Step 5: commit** `test: minimal AST→HTML renderer for conformance harness`.

### Task 5: W1-T26b — normalizeHTML
**blockedBy:** none. **Files:** append to `ConformanceHTML.swift`, `NormalizeHTMLTests.swift`.
**Interfaces:** `func normalizeHTML(_ s: String) -> String` — collapse whitespace runs to a single space, trim, so insignificant formatting differences don't fail conformance (fix K9/M12).

- [ ] **Step 1 tests:** `normalizeHTML("<p>a   b</p>\n")` == `"<p>a b</p>"`; preserves `<pre>` content? (decision: do NOT special-case `<pre>`; conformance compares normalized — document any divergence as known-skip).
- [ ] **Step 5: commit** `test: HTML normalization helper`.

### Task 6: W1-T26c — Conformance fixtures + Package resources + decoder
**blockedBy:** none. **Files:** `Tests/MarkdownASTTests/Resources/commonmark-spec.json` (download), `Resources/gfm-spec.json` (download official GFM spec — fix F3-MAJOR; do NOT hand-author), modify `Package.swift` test target `resources: [.copy("Resources")]`, `ConformanceTests.swift` skeleton with `loadSpec`.

- [ ] **Step 1:** `mkdir -p Tests/MarkdownASTTests/Resources && curl -sL https://spec.commonmark.org/0.31.2/spec.json -o Tests/MarkdownASTTests/Resources/commonmark-spec.json && curl -sL https://raw.githubusercontent.com/github/cmark-gfm/master/test/gfm-spec.json -o Tests/MarkdownASTTests/Resources/gfm-spec.json`. Add `resources: [.copy("Resources")]` to the test target. `SpecCase: Decodable { markdown, html, example, section }`.
- [ ] **Step tests:** `loadSpec("commonmark-spec")` returns non-empty; example 1 parses without crash.
- [ ] **Step 5: commit** `test: conformance fixtures and resource wiring`.

---

## Wave 2 — block dispatcher skeleton (after W1-T3)

### Task 7: W2-T4 — BlockParser skeleton + paragraphs (Pass A, raw leaves)
**blockedBy:** W1-T3. **Files:** `RawBlock.swift`, `BlockParser.swift`, `MarkdownParser.swift` (wire Pass A only), `ParagraphTests.swift`.
**Interfaces:** `indirect enum RawBlock` (internal) mirroring block structure but leaves hold `raw: String`:

```swift
indirect enum RawBlock: Equatable {
    case heading(level: Int, raw: String)
    case paragraph(raw: String)
    case blockQuote(blocks: [RawBlock])
    case list(RawList)
    case codeBlock(language: String?, code: String)
    case thematicBreak
    case table(RawTable)
    case definitionList([RawDefinition])
}
struct RawList: Equatable { var kind: MarkdownList.Kind; var isTight: Bool; var items: [RawListItem] }
struct RawListItem: Equatable { var blocks: [RawBlock]; var task: TaskState? }
struct RawTable: Equatable { var alignments: [MarkdownTable.Alignment]; var header: [[String]]; var rows: [[String]] }
struct RawDefinition: Equatable { var term: String; var details: [[RawBlock]] }
```

`struct BlockParser { let defs: DefinitionStore; func parse(_ lines: [String], depth: Int) -> [RawBlock] }`. At this wave it only emits `.paragraph(raw)`; **per-line text is trimmed of leading/trailing whitespace before join** (fix M10). `MarkdownParser.parse` wires: `splitIntoLines` → map `expandTabs` → `BlockParser(defs:).parse(...)` → (Pass B resolver stub returns `[]` for now, filled in W6-T16b).

- [ ] **Step 1 failing tests:** `singleParagraph` (`"Hello world"` → after Pass B `.paragraph([.text("Hello world")])` — but Pass B not yet wired, so assert on a temporary `parseRaw` helper exposing `[RawBlock]` OR defer the `.text` assertion to W6-T16b and here assert `[.paragraph(raw: "Hello world")]` via an internal test helper). `paragraphsSeparatedByBlankLine`; `consecutiveLinesJoinIntoOneParagraph` (joined with `\n`, **leading/trailing ws per line trimmed** — fix M10: `"  a  \n  b  "` → raw `"a\nb"`).
- [ ] **Step 3: Implement** dispatcher skeleton: index-based `while i < arr.count`, blank-line → flush, else paragraph-accumulate. Trim each line's leading/trailing whitespace when appending (but keep the joined `\n`).
- [ ] **Step 5: commit** `feat: block scanner skeleton with paragraph accumulation (Pass A)`.

---

## Wave 3 — block constructs (after W2-T4; 7 parallel via per-file split)

> **Dispatch order (CommonMark-correct, after fence handling):** setext (only if paragraph pending) →
> thematic break → ATX heading → fenced code → block quote → table (only if `paragraph.isEmpty` —
> GFM spec grants tables NO paragraph-interruption capability, fix F7/K2-adjacent) → link reference
> definition (only if `paragraph.isEmpty` — §6.1 "cannot interrupt a paragraph") → footnote definition →
> indented code (only if `paragraph.isEmpty` — cannot interrupt) → list (with thematic-break guard, K2)
> → definition list → paragraph. `isBlockStart` gates lazy continuation (K3). `stripUpTo3Spaces` gates
> indentation (M3). `canInterruptParagraph` gates list starts (M4).

### Task 8: W3-T5 — ATX headings  (blockedBy: W2-T4)
**Files:** `BlockParser.swift` (+ use `stripUpTo3Spaces` from W3-Tcont helpers — see below), `HeadingTests.swift`.
**Fixes:** ≤3 leading spaces via `stripUpTo3Spaces` (M3); closing `#` run stripped only if preceded by space.
- [ ] **Tests:** levels 1–6; `## Title ##` → `Title`; `####### nope` → paragraph; `    # H` (4 spaces) → NOT heading (indented code / paragraph per context); `  # H` (2 spaces) → heading; `headingInterruptsParagraph`.
- [ ] **Impl:** `atxHeading(_ line:)` using `stripUpTo3Spaces(line)`; require 1–6 `#` then space-or-EOL; strip optional trailing `#` run (only if a space precedes it).
- [ ] **commit** `feat: ATX heading parsing`.

### Task 9: W3-T6 — Thematic breaks  (blockedBy: W2-T4)
**Files:** `BlockParser.swift`, `ThematicBreakTests.swift`.
**Fixes:** ≤3 leading spaces (M3); tabs handled via expandTabs already; `- - -`/`* * *`/`___` → hr.
- [ ] **Tests:** `---`, `***`, `___`, `- - -`, `* * *` → `.thematicBreak`; `--` → paragraph; `    ---` (4 spaces) → NOT hr.
- [ ] **Impl:** `thematicBreak(_ line:) -> Bool`: strip ≤3 spaces, filter spaces/tabs, ≥3 chars, all same (`-`/`*`/`_`).
- [ ] **commit** `feat: thematic break parsing`.

### Task 10: W3-Tcont — Container/indentation helpers  (blockedBy: W2-T4)
**Files:** `Containers.swift`, `ContainersTests.swift`.
**Interfaces:** `func stripUpTo3Spaces(_ line: Substring) -> Substring` (drop 0–3 leading spaces; ≥4 left intact for indented-code detection — fix M3); `func isBlockStart(_ line: Substring) -> Bool` (true if line begins ATX heading, setext underline, fenced code, thematic break, blockquote `>`, list marker, table-with-delimiter-lookahead, `:` definition detail, link/footnote def — used to gate lazy continuation, fix K3); `func canInterruptParagraph(_ line: Substring) -> Bool` (true for ATX, thematic break, blockquote, fenced code, **unordered** list start, **ordered** list start with number 1 AND non-empty item — fix M4; false for ordered start ≠1, empty item, indented code, setext, table, link-ref-def).
- [ ] **Tests:** `stripUpTo3Spaces("   # H")` → `"# H"`; `stripUpTo3Spaces("    code")` → `"    code"` (4 kept); `isBlockStart("# H")` true, `isBlockStart("plain")` false; `canInterruptParagraph("2. x")` false, `canInterruptParagraph("- x")` true, `canInterruptParagraph("1. x")` true, `canInterruptParagraph("-   ")` false (empty item).
- [ ] **commit** `feat: container/interruption helpers`.

### Task 11: W3-T8 — Fenced code blocks  (blockedBy: W2-T4)
**Files:** `BlockParser.swift`, `FencedCodeTests.swift`.
**Fixes:** record opening indent and strip that many leading spaces from each content line (M6); closing fence length ≥ opening; closing fence may have ≤3 leading spaces and only trailing whitespace after the run; opening fence may be indented ≤3 (M6/F8/F9).
- [ ] **Tests:** backtick + tilde fences; info string first word = language; `# not a heading` inside stays literal; unclosed runs to EOF; `   ```\n   code\n   ```` (3-space indent) → content `"code"` (indent stripped); closing fence shorter than opening → not a closer; trailing spaces after closing fence allowed; ` ```x ` info string with trailing spaces stripped.
- [ ] **Impl:** `struct Fence { char; count; language: String?; indent: Int }`; `fenceOpener` records `indent = leadingSpaces` (≤3 else nil); `isFenceCloser` strips ≤3 leading spaces, requires run of same char ≥ count, then only whitespace.
- [ ] **commit** `feat: fenced code block parsing with indent/closing rules`.

### Task 12: W3-T10 — Block quotes (nested)  (blockedBy: W2-T4, W3-Tcont)
**Files:** `BlockParser.swift`, `BlockQuoteTests.swift`.
**Fixes:** lazy continuation gated by `!isBlockStart(line)` (K3/F4) — a heading/fence/new-list after `> para` starts a sibling, not a quote continuation.
- [ ] **Tests:** `> hello`; `> > deep`; `> # H` → heading inside quote; `> para\n# H` → quote(paragraph) + heading (NOT heading inside quote); `> para\nlazy` → quote with joined paragraph (lazy ok); `> para\n- item` → quote(paragraph) + list (lazy blocked).
- [ ] **Impl:** branch after fence handling: strip `>` + optional one space; collect inner lines while marker present OR (`!stripped.isEmpty` AND `!isBlockStart(l)`); recurse `parse(inner, depth+1)`.
- [ ] **commit** `feat: nested block quote parsing with lazy-continuation guard`.

### Task 13: W3-T13 — GFM tables  (blockedBy: W2-T4)
**Files:** `TableParser.swift`, `BlockParser.swift`, `TableTests.swift`.
**Fixes:** only start a table when `paragraph.isEmpty` (F7 — tables cannot interrupt paragraphs); escaped pipe `\|` unescaped in cell text (M8); delimiter row tightened to `:?-+:?` per cell with ≥1 `-`, row only pipes/dashes/colons/space (M8); cell count normalized to header width.
- [ ] **Tests:** `simpleTable`; `tableAlignments` (`:--`, `:-:`, `--:`); escaped pipe `| a \\| b |` → cell `"a | b"`; `tableRequiresBlankLineBefore` (`"para\n| a |\n| - |"` → paragraph, NOT table); extra/missing cells normalized.
- [ ] **Impl:** `splitTableRow` (track `\` escapes, unescape `\|`→`|` after split, keep other `\x` literal for inline pass); `delimiterAlignments` (validate each cell matches `:?-+:?` with ≥1 `-`, else return nil); in dispatcher, guard `paragraph.isEmpty` AND `i+1 < count` AND `delimiterAlignments(arr[i+1]) != nil`.
- [ ] **commit** `feat: GFM table parsing with escaped pipes and paragraph guard`.

### Task 14: W3-T15 — Definition lists  (blockedBy: W2-T4)
**Files:** `BlockParser.swift`, `DefinitionListTests.swift`.
**Fixes:** each `: detail` line is a SEPARATE detail (`details: [[MarkdownBlock]]` with multiple entries) — fix M5/F13; indented continuation lines (not starting with `:`) attach to the current detail; consecutive term/detail groups merge into one list.
- [ ] **Tests:** `Term\n: Definition` → 1 detail; `A\n: one\n: two` → 2 details; `Term\n: line1\n  line2` → 1 detail with multi-line content; `A\n: one\nB\n: two` → 2 definitions in one list.
- [ ] **Impl:** when current line is `: …` and a one-line pending paragraph exists (the term): capture term, then loop collecting `: ` lines each starting a new detail array entry, plus indented continuation lines folded into the current detail; merge into trailing `.definitionList` or start one.
- [ ] **commit** `feat: definition list parsing with per-colon details`.

### Task 15: W3-T14wire — Wire DefinitionStore + link/footnote def collection  (blockedBy: W1-T14store, W2-T4)
**Files:** `BlockParser.swift`, `DefinitionStore.swift` (add parsers), `DefinitionTests.swift`.
**Interfaces:** `linkReferenceDefinition(_:depth:)` (handles `<dest>`, `"…"`/`'…'`/`(…)` titles, multi-line titles via continuation, trailing-junk rejection, escapes — fixes M7/L14-C1/M11); `footnoteDefinition(_:from:depth:)` (multi-paragraph body via peek-ahead across blank lines to next indented line — fix M13/F12).
- [ ] **Tests:** `[id]: https://example.com "T"` collected + removed from blocks; `[id]: <url with spaces> "T"`; footnote single-line + multi-paragraph (`[^1]: a\n\n    para2` → 2 blocks); footnote body stops at dedent; link-ref-def does NOT interrupt paragraph (`"para\n[id]: x"` → paragraph + def).
- [ ] **Impl:** in dispatcher before paragraph accumulation, guarded by `paragraph.isEmpty`; `linkReferenceDefinition` parses label, `:`, destination (bare or `<…>`), optional title (quoted or `(...)`, may continue on next line if not closed), reject leftover non-whitespace; `footnoteDefinition` collects `[^id]:` body + indented continuation lines, peeking past blank lines to detect multi-paragraph bodies.
- [ ] **commit** `feat: collect link reference and footnote definitions`.

---

## Wave 4 — dependent blocks (after Wave 3)

### Task 16: W4-T7 — Setext headings  (blockedBy: W3-T6)
**Files:** `BlockParser.swift`, `SetextHeadingTests.swift`.
**Fixes:** setext checked first (only when paragraph pending) so `---` alone → thematic break, `Title\n---` → h2 (ordering vs W3-T6); ≤3 leading spaces on underline (M3); tabs in underline handled.
- [ ] **Tests:** `Title\n===` → h1; `Title\n---` → h2; `---` alone → thematic break; `a\nb\n===` → h1 with joined text; `Title\n   ===` (3 spaces) ok; `Title\n    ===` (4 spaces) → paragraph (not setext).
- [ ] **commit** `feat: setext heading parsing`.

### Task 17: W4-T9 — Indented code blocks  (blockedBy: W3-T8)
**Files:** `BlockParser.swift`, `IndentedCodeTests.swift`.
**Fixes:** only when `paragraph.isEmpty` (cannot interrupt — §4.4); strip first 4 spaces; trailing blank lines trimmed; clear `isIndentedCode` predicate (fix the v1 ternary precedence bug, review swift-compile F13).
- [ ] **Tests:** `    let x = 1\n    let y = 2` → code `"let x = 1\nlet y = 2"`; `text\n    more` → paragraph (lazy, not code); blank line inside indented code preserved then trimmed at edges.
- [ ] **Impl:** `isIndentedCode = line.hasPrefix("    ") && !line.dropFirst(4).allSatisfy { $0 == " " }`.
- [ ] **commit** `feat: indented code block parsing`.

### Task 18: W4-T11a — List marker recognizer  (blockedBy: W2-T4)
**Files:** `ListParser.swift`, `ListMarkerTests.swift`.
**Interfaces:** `func listMarker(_ line: Substring) -> ListMarker?` — bullet `-`/`+`/`*`; ordered `N.`/`N)` (≤9 digits); `markerWidth` capped so spaces-after-marker ≥5 are treated as 1 (fix F14-MINOR); leading indent <4.
- [ ] **Tests:** all bullet chars; ordered `1.`/`1)`/`3.`; `123456789.` ok, `1234567890.` nil (>9 digits); `markerWidth` for `-  x` = 2, for `-   x` = 4 (cap: 5+ spaces → width 2, content keeps the rest); `    - x` (4 spaces) → nil (indented).
- [ ] **commit** `feat: list marker recognizer`.

### Task 19: W4-T11e — Dispatch ordering fix — thematic break BEFORE list  (blockedBy: W3-T6, W4-T11a)
**Files:** `BlockParser.swift`.
**Fix:** K2 — in the dispatcher, the thematic-break check runs **before** the list branch (or the list branch guards `!thematicBreak(line)`). Verify `- - -`/`* * *` → `.thematicBreak` not a list.
- [ ] **Tests:** re-run `ThematicBreakTests` (`- - -`, `* * *`) against full dispatcher → PASS; `- a` → list.
- [ ] **commit** `fix: dispatch thematic break before list`.

---

## Wave 5 — lists (after W4-T11a)

### Task 20: W5-T11b — Flat list parsing (bullet only, single level)  (blockedBy: W4-T11a)
**Files:** `BlockParser.swift` (`parseList`), `ListTests.swift`.
**Interfaces:** `func parseList(_ arr: [String], from: Int, firstMarker:, depth:) -> (RawBlock, Int)` — collects same-kind items; item content = marker remainder + continuation lines indented ≥ `markerWidth`.
- [ ] **Tests:** `bulletList` (`- a\n- b`); `orderedListStart` (`3. x\n4. y` → `ordered(start: 3)`, 2 items).
- [ ] **commit** `feat: flat list parsing`.

### Task 21: W5-T11c — Nested lists  (blockedBy: W5-T11b)
**Files:** `BlockParser.swift`, `ListTests.swift`.
**Interfaces:** item content parsed via recursive `parse(itemLines, depth+1)` → nesting for free; lazy continuation gated by `!isBlockStart(line)` (K3) — a heading/fence/new top-level list inside item content that isn't indented to `markerWidth` starts a sibling.
- [ ] **Tests:** `nestedList` (`- a\n  - b`); `- a\n# H` → list(item a) + heading (NOT heading inside item).
- [ ] **commit** `feat: nested list parsing`.

### Task 22: W5-T11d — Tight/loose rework  (blockedBy: W5-T11b)
**Files:** `BlockParser.swift`, `ListTests.swift`.
**Fix:** K8/C5 — a list is loose if **any** blank line separates two block-level children: between items OR between blocks inside an item (excluding a trailing blank before the list ends). Remove the no-op `isTight = isTight && true`. Set `isTight = false` when a blank line appears inside an item's collected lines (between non-blank content) and at item boundaries.
- [ ] **Tests:** `looseListWhenBlankBetweenItems` (`- a\n\n- b` → loose); `tightListNoBlanks` (`- a\n- b` → tight); `looseWhenBlankInsideItem` (`- a\n\n  b` → loose, multi-paragraph item); `tightWithTrailingBlank` (`- a\n- b\n\n` → tight, trailing blank ignored).
- [ ] **commit** `feat: tight/loose list detection`.

### Task 23: W5-T12 — GFM task list items  (blockedBy: W5-T11b)
**Files:** `BlockParser.swift`, `TaskListTests.swift`.
**Interfaces:** after parsing an item's blocks, if the first paragraph's first text starts with `[ ]`/`[x]`/`[X]` (+ optional trailing space), set `item.task` and strip the marker.
- [ ] **Tests:** `- [ ] todo` → `.unchecked` + text `"todo"`; `- [x] done` → `.checked`; `- [X] done`; `- [x]  done` (2 spaces) → text `"done"`; `- normal` → `task == nil`.
- [ ] **commit** `feat: GFM task list items`.

---

## Wave 6 — inline-side gate + Pass B wiring (after W3-T14wire, W2-T4)

### Task 24: W6-T16 — InlineParser scaffold — text, escapes  (blockedBy: W3-T14wire, W2-T4)
**Files:** `InlineParser.swift`, `InlineTextTests.swift`.
**Interfaces:** `struct InlineParser { let defs: DefinitionStore; func parse(_ text: String, depth: Int) -> [MarkdownInline] }`. At this wave: plain text + backslash escapes (`\` + ASCII punctuation → the punct char; `\` + non-punct → literal `\` + char). **Does NOT wire into BlockParser yet** — tested via a direct internal helper. Eager wiring is removed (K1); Pass B owns all inline calls.
- [ ] **Tests:** `plainText`; `backslashEscape` (`\\*not emphasis\\*` → `.text("*not emphasis*")`); `backslashBeforeNormalCharKept` (`a\\b` → `.text("a\\b")`).
- [ ] **Impl:** char-array scan; `escapable = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_\`{|}~")`.
- [ ] **commit** `feat: inline parser scaffold with backslash escapes`.

### Task 25: W6-T16b — Pass B — deferred inline resolution  (blockedBy: W6-T16, W1-T14store)  ★ K1
**Files:** `MarkdownParser.swift` (resolver), `InlineParser.swift`, `PassBTests.swift`.
**This is the architectural fix for K1 and the prerequisite for Tasks 21/25.** After Pass A produces `[RawBlock]` and `DefinitionStore` is complete, recursively walk the `RawBlock` tree and produce `[MarkdownBlock]`, calling `InlineParser(defs:).parse(raw)` on every leaf: paragraph raw, heading raw, table header/row cells, definition terms, definition detail blocks (recurse), list item blocks (recurse), blockquote blocks (recurse), **and every `FootnoteDefinition` body in `defs.footnotes`** (resolve its `[RawBlock]` → `[MarkdownBlock]`). Carry `depth` for the recursion guard.

```swift
public static func parse(_ source: String) -> MarkdownDocument {
    let lines = splitIntoLines(source).map { expandTabs($0) }
    let defs = DefinitionStore()
    let rawBlocks = BlockParser(defs: defs).parse(lines, depth: 0)
    let blocks = resolveInlines(rawBlocks, defs: defs, depth: 0)
    let footnotes = defs.footnotes.map { FootnoteDefinition(id: $0.id, blocks: resolveInlines($0.rawBody, defs: defs, depth: 0)) }
    return MarkdownDocument(blocks: blocks, footnotes: footnotes)
}

func resolveInlines(_ raw: [RawBlock], defs: DefinitionStore, depth: Int) -> [MarkdownBlock] {
    guard depth < maxDepth else { return raw.map { rawToLiteralBlock($0) } }   // overflow fallback
    let inline = InlineParser(defs: defs)
    return raw.map { resolveBlock($0, inline: inline, defs: defs, depth: depth) }
}
```

`FootnoteDefinition` in the store holds `rawBody: [RawBlock]` (internal); the public `FootnoteDefinition.blocks` is the resolved form. (Adjust W1-T14store so the store's internal footnote type carries `rawBody`; expose resolved `footnotes` only via `parse`.)

- [ ] **Tests:** forward reference link resolves: `[Swift][sw]\n\n[sw]: https://swift.org` → `[.link(destination: "https://swift.org", title: nil, content: [.text("Swift")])]` (this test FAILED in v1 — now passes); forward footnote: `Text[^1]\n\n[^1]: note` → `[.text("Text"), .footnoteReference(id: "1")]` + `doc.footnotes` resolved; backward reference still works; nested blockquote paragraph inline-parsed after Pass A completes.
- [ ] **Impl:** `resolveBlock` switches on `RawBlock`: leaves → `InlineParser.parse(raw)`; containers → recurse `resolveInlines`. Update `MarkdownParser.parse` pipeline (remove any eager inline calls from `BlockParser`).
- [ ] **commit** `feat: Pass B deferred inline resolution (fixes forward references)`.

### Task 26: W6-T17 — Inline code spans  (blockedBy: W6-T16)
**Files:** `InlineParser.swift`, `CodeSpanTests.swift`.
**Interfaces:** matched backtick runs of equal length; single leading/trailing space stripped only when content non-blank and both edges are spaces; backslashes literal inside code spans.
- [ ] **Tests:** `a \`code\` b` → `[.text("a "), .code("code"), .text(" b")]`; double backtick allows backtick inside (`` ``a`b`` `` → `.code("a`b")`); `\`\\\*\`` → `.code("\\*")`; unmatched backticks literal (`` `no close `` → text).
- [ ] **Impl:** tokenize scan: on `` ` `` measure run, find equal-length closing run, emit `.code` with space-trim rule; else literal.
- [ ] **commit** `feat: inline code spans`.

---

## Wave 7 — emphasis split (after W6-T17)

### Task 27: W7-T18a — InlineToken model + tokenizer  (blockedBy: W6-T17)
**Files:** `EmphasisResolver.swift`, `InlineParser.swift`, `EmphasisTokenizerTests.swift`.
**Interfaces:**

```swift
enum InlineToken: Equatable {
    case literal(MarkdownInline)                                  // text/code/link already resolved
    case delim(char: Character, count: Int, origCount: Int, canOpen: Bool, canClose: Bool)
}
```

`InlineParser.parse` builds `[InlineToken]`: `*`/`_` runs (length ≥1) and `~~` runs (length ≥2) become `.delim` with flanking classification from neighboring chars; code spans / autolinks / links / text become `.literal`. Text runs are merged into one `.literal(.text(...))` between delimiters.

- [ ] **Tests:** tokenizer emits one `.delim(char:"*", count:2, …)` for `**`; text between delimiters is one literal; `~~` → delim char `~` count 2; single `~` → literal (not a delimiter).
- [ ] **commit** `feat: inline tokenizer producing delimiter tokens`.

### Task 28: W7-T18b — classifyFlanking (pure)  (blockedBy: none — parallel with W7-T18a)
**Files:** `EmphasisResolver.swift`, `FlankingTests.swift`.
**Fixes K7:** flanking is char-aware. For `*`/`~`: standard left/right-flanking. For `_`: can open only if left-flanking AND (not right-flanking OR preceded by punctuation); can close only if right-flanking AND (not left-flanking OR followed by punctuation). Uses the **CommonMark punctuation set** (Unicode general categories P) — note Swift's `isPunctuation`/`isSymbol` differ; use an explicit `isCommonMarkPunctuation(_:)` (fix L18-C4 minor).

```swift
func classifyFlanking(char: Character, before: Character?, after: Character?) -> (canOpen: Bool, canClose: Bool) {
    let beforeWS = before == nil || before!.isWhitespace
    let afterWS  = after  == nil || after!.isWhitespace
    let beforeP  = isCommonMarkPunctuation(before)
    let afterP   = isCommonMarkPunctuation(after)
    let leftFlanking  = !afterWS  && (!afterP  || beforeWS || beforeP)
    let rightFlanking = !beforeWS && (!beforeP || afterWS  || afterP)
    switch char {
    case "_":
        let canOpen  = leftFlanking  && (!rightFlanking || beforeP)
        let canClose = rightFlanking && (!leftFlanking  || afterP)
        return (canOpen, canClose)
    default:  // "*", "~"
        return (leftFlanking, rightFlanking)
    }
}
```

- [ ] **Tests:** `*a*` opener left-flanking, closer right-flanking; `a_b_c` both `_` are left&right flanking → canOpen=false for the first (preceded by non-punct) → no emphasis (K7); `_a_` at start → canOpen; `a_ _b` (space before) → first `_` right-flanking only.
- [ ] **commit** `feat: char-aware flanking classification with intraword underscore rules`.

### Task 29: W7-T18e — Coalescing pass  (blockedBy: none — parallel)  ★ K6
**Files:** `EmphasisResolver.swift`, `CoalescingTests.swift`.
**Interfaces:** `func coalesceText(_ inlines: [MarkdownInline]) -> [MarkdownInline]` — merge consecutive `.text` nodes into one; recurse into children of `.emphasis`/`.strong`/`.strikethrough`/`.link`. Applied at the end of `InlineParser.parse` (after `processEmphasis`) and after link construction.
- [ ] **Tests:** `[.text("a "), .text("*"), .text(" b")]` → `[.text("a * b")]` (fixes v1 `unmatchedStarIsLiteral`); `[.text("x"), .emphasis([.text("a"), .text("b")]), .text("y")]` → `[.text("x"), .emphasis([.text("ab")]), .text("y")]`.
- [ ] **commit** `feat: coalesce adjacent text nodes`.

---

## Wave 8 — emphasis core + link helpers (after W7-T18a + W7-T18b)

### Task 30: W8-T18c — resolveEmphasis — canonical process_emphasis  (blockedBy: W7-T18a, W7-T18b)  ★ K4/K5
**Files:** `EmphasisResolver.swift`, `EmphasisTests.swift`.
**Fixes K4 + K5:** implement the canonical CommonMark `process_emphasis` with a delimiter linked list, `openers_bottom` keyed by `(char, canOpen, length % 3)`, and the **rule of 3**: a pairing is forbidden when one delimiter can both open and close AND `(openerOrigCount + closerOrigCount) % 3 == 0` AND NOT `(openerOrigCount % 3 == 0 && closerOrigCount % 3 == 0)`.

```swift
func processEmphasis(_ tokens: [InlineToken]) -> [InlineInline]   // returns [MarkdownInline]
```

Reference structure (doubly-linked delimiter list over token indices):

```swift
// 1. Collect delimiter indices in order.
// 2. closer = first delimiter; walk forward.
// 3. For a closer that canClose:
//    opener = closer.prev; walk back over same-char canOpen delimiters,
//    stopping at openers_bottom[(char, false, closerOrigCount % 3)] (and the (…, true, …) variant).
//    For each candidate opener: if rule-of-3 forbids, continue back; else match.
//    On match: consume min(opener.count, closer.count) chars; if ≥2 on both → strong, else emphasis;
//    wrap the literals between opener and closer; decrement counts; if a side hits 0, remove it;
//    reset closer to just after opener (re-scan). Update openers_bottom for skipped openers.
// 4. On no match: record openers_bottom floor for this closer's class; advance closer.
// 5. Remaining delimiters emit as literal .text(char * remainingCount).
```

For `~` (strikethrough, W9-T19): pair only when both sides count ≥2, consume 2, produce `.strikethrough`.

- [ ] **Tests (Step 1, exact):** `*hi*` → emphasis; `_hi_` → emphasis; `**hi**` → strong; `*a **b** c*` → emphasis(text, strong, text); `intrawordUnderscoreNotEmphasis` (`a_b_c` → `.text("a_b_c")`); `unmatchedStarIsLiteral` (`a * b` → `.text("a * b")`). **Plus rule-of-3 ladder:** `***a***` → strong(emphasis(a)); `*a**b**c*`; `**a*b*c**`; `foo******bar*baz*bug`; `***a b***c**` (CM examples 413–427). Each `#expect` added one at a time until green.
- [ ] **Impl:** write the linked-list resolver; if a sub-case fails, do NOT ship — add the failing CM example as a test and fix. This is the riskiest unit; budget extra iterations (v1 acknowledged this and punted; v2 makes canonical the primary impl).
- [ ] **commit** `feat: emphasis/strong via canonical process_emphasis with rule of 3`.

### Task 31: W8-T20a — Bracket/paren matchers  (blockedBy: W6-T16)
**Files:** `LinkParser.swift`, `BracketMatchTests.swift`.
**Interfaces:** `matchBracket(_ chars: [Character], openAt: Int) -> Int?` and `matchParen(...) -> Int?` — balanced depth, **backslash-escaped brackets/parens are skipped**, **code spans (backtick runs) are opaque** (a `[`/`]`/`(`/`)` inside a code span does not count — fix L20-C3). Returns the matching close index or nil.
- [ ] **Tests:** nested `[a [b] c]` → outer close; escaped `\[` skipped; `[` inside `` `x[y]z` `` ignored.
- [ ] **commit** `feat: bracket/paren matching with escape and code-span opacity`.

### Task 32: W8-T20b — Destination + title parsing  (blockedBy: W6-T16)
**Files:** `LinkParser.swift`, `DestinationTitleTests.swift`.
**Fixes M7/L20-C2/L20-C3:** `splitDestinationAndTitle(_:) -> (dest: String, title: String?)` handles: `<dest>` with spaces; bare dest with balanced parens; title delimited by `"…"`, `'…'`, or `(…)`; **reject when leftover non-whitespace remains after title**; handle `\` escapes in dest/title. `extractTitle` returns nil on malformed.
- [ ] **Tests:** `(https://a.com "T")`; `(<https://a.com/x y> "T")`; `(https://a.com/(x))` (balanced parens in dest); `("only title")` → dest empty? (decision: invalid → nil link); `(https://a.com "T" junk)` → reject (leftover); `(https://a.com 'T')`; `(https://a.com (T))`.
- [ ] **commit** `feat: link destination and title parsing`.

---

## Wave 9 — dependent inline (after W8-T18c; fan-out)

### Task 33: W9-T18d — `_` intraword wiring into resolver  (blockedBy: W8-T18c)
**Files:** `EmphasisResolver.swift`, `UnderscoreTests.swift`.
**Verifies K7 end-to-end** through the resolver (flanking comes from W7-T18b; this confirms the resolver honors canOpen/canClose for `_`).
- [ ] **Tests:** `a_b_c` → text; `_a_` → emphasis; `a_b_` → text (trailing `_` not closer); `_a_b_` → emphasis(emphasis? per CM) — pin to CM example 418; `foo_bar_baz` → text.
- [ ] **commit** `feat: intraword underscore emphasis rules`.

### Task 34: W9-T19 — Strikethrough (GFM)  (blockedBy: W8-T18c)
**Files:** `EmphasisResolver.swift`, `InlineParser.swift`, `StrikethroughTests.swift`.
**Interfaces:** `~~` runs (length ≥2) tokenize as `.delim(char: "~", …)`; resolver pairs them consuming 2 each → `.strikethrough(inner)`. Single `~` is literal. Mixed-length `~~~` (review minor) — decision: require exact length-2 match for v1, longer runs literal (document).
- [ ] **Tests:** `~~gone~~` → strikethrough; `a ~ b` → text; `~~~nope~~~` → text (v1 decision).
- [ ] **commit** `feat: GFM strikethrough`.

### Task 35: W9-T20c — Inline link/image parser  (blockedBy: W8-T20a, W8-T20b)
**Files:** `LinkParser.swift`, `InlineParser.swift`, `LinkTests.swift`.
**Interfaces:** `parseInlineLinkOrImage(_ chars: [Character], from: Int) -> (MarkdownInline, Int)?` — `[text](dest "title")` and `![alt](src "title")`; link text parsed recursively via `InlineParser.parse`; links/images tokenized as `.literal` **before** emphasis resolution (link precedence). **Image alt = stripped text content of the bracket interior** (parse interior inlines, reduce to a plain string — fix L20-C1), not raw bracket text.
- [ ] **Tests:** `inlineLink`; `inlineLinkWithTitle`; `inlineImage` (alt `"alt"`); `emphasisInsideLinkText` (`[*hi*](u)` → link with emphasis content).
- [ ] **commit** `feat: inline links and images`.

### Task 36: W9-T22 — CommonMark autolinks  (blockedBy: W8-T18c)
**Files:** `Autolink.swift`, `InlineParser.swift`, `AutolinkTests.swift`.
**Fixes:** define `indexOf`-equivalent as an inline scan (fix F1-swift-compile/C7); URI scheme `^[a-zA-Z][a-zA-Z0-9+.-]*:` with non-empty after-colon and no whitespace/`<>` (fix L22-C1); email `local@domain.tld` with exactly one `@` and a dot in the domain. Email autolink stores `mailto:` prefix? — decision: store raw `a@b.com` (matches v1); document divergence from cmark (review F11-test minor).
- [ ] **Tests:** `<https://swift.org>` → `.autolink(url: "https://swift.org")`; `<a@b.com>` → `.autolink(url: "a@b.com")`; `<mailto:>` → literal (empty after colon); `<no scheme>` → literal.
- [ ] **commit** `feat: CommonMark autolinks`.

---

## Wave 10 — wiring + extended (after Wave 9)

### Task 37: W10-T20d — Image form + alt reduction  (blockedBy: W9-T20c)
**Files:** `LinkParser.swift`, `ImageTests.swift`.
**Fix L20-C1:** image alt is the text content of `![… ]` after parsing interior inlines and stripping markup (e.g. `![*alt*](x)` → alt `"alt"`).
- [ ] **Tests:** `![*alt*](x)` → `.image(source: "x", title: nil, alt: "alt")`; `![a b](x)` → alt `"a b"`.
- [ ] **commit** `feat: image alt text reduction`.

### Task 38: W10-T20e — Wire links/images into tokenizer  (blockedBy: W9-T20c, W10-T20d, W8-T18c)
**Files:** `InlineParser.swift`, `LinkTests.swift`.
**Interfaces:** in the tokenizer, before treating `[`/`!` as text, attempt `parseInlineLinkOrImage`; on success push `.literal(node)` and advance. Run `coalesceText` after.
- [ ] **Tests:** links in context with surrounding text; link followed by trailing text coalesces.
- [ ] **commit** `feat: wire inline links and images into tokenizer`.

### Task 39: W10-T21 — Reference links/images  (blockedBy: W10-T20e, W6-T16b)  ★ depends on K1 fix
**Files:** `LinkParser.swift`, `InlineParser.swift`, `ReferenceLinkTests.swift`.
**Interfaces:** `[text][label]`, `[text][]`, shortcut `[label]` resolve via `defs.link(for:)`. Unresolved → literal text. **Forward references now resolve** because Pass B runs after the store is complete (W6-T16b).
- [ ] **Tests:** `fullReferenceLink` (`[Swift][sw]\n\n[sw]: …`); `collapsedReference` (`[sw][]`); `shortcutReference` (`[sw]`); `unresolvedReferenceIsLiteral` (`[missing]`); **forward-reference** (definition after use); reference image `![alt][im]`.
- [ ] **commit** `feat: reference links and images`.

### Task 40: W10-T23 — GFM extended autolinks  (blockedBy: W9-T22)
**Files:** `Autolink.swift`, `InlineParser.swift`, `ExtendedAutolinkTests.swift`.
**Fixes M9/F2-MAJOR:** bare `http://`/`https://`/`www.` URLs **and bare emails** become `.autolink`; strip trailing punctuation `?!.,:*_~` and unmatched trailing `)` (balanced-paren aware); validate domain has a dot for `www.`/bare URLs.
- [ ] **Tests:** `see https://swift.org now` → text + autolink + text; `at www.swift.org.` → autolink + `.text(".")`; `(https://a.com)` → `(` + autolink + `)` (balanced); `https://a.com.` → autolink + `.`; bare email `contact a@b.com now` → autolink (F2-MAJOR); `https://a.com!` → autolink + `!`.
- [ ] **commit** `feat: GFM extended bare autolinks (urls and emails)`.

### Task 41: W10-T24 — Hard & soft breaks  (blockedBy: W8-T18c)
**Files:** `InlineParser.swift`, `BreakTests.swift`.
**Fixes L24-C1/M1:** `\n` inside a paragraph → `.softBreak`; line ending with ≥2 spaces → `.hardBreak` (trim the spaces); `\\\n` → `.hardBreak` (handle **before** the generic escape rule). **Update the v1 multi-line `.text` tests from W2-T4 / W4-T7 / W4-T9** that asserted embedded `\n` in `.text`: those now produce `.softBreak`. Call out the rewrite in this task's tests.
- [ ] **Tests:** `softBreak` (`a\nb` → `[.text("a"), .softBreak, .text("b")]`); `hardBreakTwoSpaces` (`a  \nb`); `hardBreakBackslash` (`a\\\nb`); re-assert `consecutiveLinesJoinIntoOneParagraph` now yields softBreak-separated inlines (update W2-T4 test).
- [ ] **commit** `feat: hard and soft line breaks (update multi-line paragraph tests)`.

### Task 42: W10-T25 — Footnote references (inline) + multi-paragraph bodies  (blockedBy: W10-T20e, W6-T16b, W3-T14wire)
**Files:** `InlineParser.swift`, `DefinitionStore.swift`, `FootnoteReferenceTests.swift`.
**Fixes:** `[^id]` → `.footnoteReference(id:)`. **Spec §5 says unconditional**; v1 added a "only when def exists" condition (F8-MINOR). Decision for v2: emit `.footnoteReference(id:)` whenever the syntax `[^id]` matches **and a definition exists**; if no definition, literal text (keeps v1 test, document the deviation from spec §5 line 171 in the doc comment — revisit if user objects). Multi-paragraph bodies already handled in W3-T14wire; here we add the inline reference token and verify the full round-trip.
- [ ] **Tests:** `footnoteReferenceResolves` (`Text[^1]\n\n[^1]: note`); `unknownFootnoteReferenceIsLiteral` (`Text[^x]`); multi-paragraph footnote body renders 2 blocks.
- [ ] **commit** `feat: inline footnote references with multi-paragraph bodies`.

---

## Wave 11 — conformance + final gate (after all feature waves)

### Task 43: W11-T26d — Parameterized conformance harness + KnownSkips  (blockedBy: W1-T26a/b/c + all feature waves 5–25)
**Files:** `ConformanceTests.swift`, `KnownSkips.swift`.
**Fixes F4-MINOR/F5-MINOR/F12-test:** use **parameterized** `@Test(arguments:)` (one test per spec example, not a loop); `KnownSkips` maps example number → reason (not a bare `Set<Int>`); include a GFM conformance test using `gfm-spec.json` (`SpecCase` with `section`).
- [ ] **Tests:** `@Test(arguments: commonMarkExamples()) func commonMarkConformance(_ c: SpecCase)` comparing `normalizeHTML(astToHTML(parse(c.markdown)))` vs `normalizeHTML(c.html)`, skipping `knownSkips` with a stated reason.
- [ ] **commit** `test: parameterized CommonMark/GFM conformance harness`.

### Task 44: W11-T26e — Triage run + populate known-skips + official GFM fixtures  (blockedBy: W11-T26d)
**Files:** `KnownSkips.swift`, feature test files.
- [ ] **Step:** run `swift test --filter Conformance`; move genuinely out-of-scope failures (HTML blocks, entity refs, nested links, info-strings-with-backticks) into `knownSkips` grouped by category with a reason; **fix any in-scope failure** by adding a targeted TDD test in the relevant feature file and correcting the parser (do not silently skip in-scope cases). Re-run until green except documented skips.
- [ ] **commit** `test: populate conformance known-skips; fix in-scope failures`.

### Task 45: W11-T27 — Final gate — build, test, lint, docs, HTML pass-through  (blockedBy: W11-T26e)
**Files:** `MarkdownParser.swift` (doc), `.swiftlint.yml` (add if absent — fix F6-MINOR), `HTMLPassThroughTests.swift` (fix F7-MINOR).
- [ ] **Step 1:** add `HTMLPassThroughTests` asserting raw HTML flows through as literal text (`<div>x</div>` → paragraph with text `<div>x</div>`); entity refs `&amp;` → literal `&amp;`.
- [ ] **Step 2:** expand `MarkdownParser` doc comment (supported constructs + documented limitations).
- [ ] **Step 3:** add `.swiftlint.yml` (or document SwiftLint as not-configured); run `swiftlint` if available and fix violations.
- [ ] **Step 4:** `swift build && swift test` — all green except documented conformance skips.
- [ ] **commit** `docs: document coverage and limitations; final gate`.

---

## Open questions (decisions applied — confirm with user before the gated waves)

1. **OQ1 — Conformance methodology (gates W11-T26d):** v2 implements AST→HTML + `normalizeHTML` for real conformance numbers (W1-T26a/b). *Alternative:* curated hand-authored AST expectations — lighter, no HTML renderer, but less exhaustive and no conformance percentage. **Default in v2:** AST→HTML.
2. **OQ2 — Extended depth (gates W3-T14wire, W3-T15, W10-T25):** v2 implements multi-paragraph footnotes, multi-line link-reference definitions, and multi-block definition-list details now. *Alternative:* document as v1 limitations. **Default in v2:** implement now.
3. **OQ3 — Definition-list `details` cardinality (gates W3-T15):** keep `details: [[MarkdownBlock]]` (multiple definitions per term). *Alternative:* simplify to `[MarkdownBlock]`. **Default in v2:** keep `[[MarkdownBlock]]`.

If the user picks an alternative for any OQ, only the gated micro-tasks change — the rest of the plan is unaffected.

---

## Self-Review (v2)

**Critical fixes applied (K1–K10):**
- K1 two-pass → W6-T16b (deferred inline walk) + removed eager wiring; gates W10-T21/T25.
- K2 dispatch order → W4-T11e (thematic break before list).
- K3 lazy continuation → W3-Tcont `isBlockStart` + W3-T10, W5-T11c.
- K4 rule of 3 → W8-T18c canonical resolver.
- K5 openers_bottom → W8-T18c canonical resolver.
- K6 coalescing → W7-T18e.
- K7 intraword `_` → W7-T18b + W9-T18d.
- K8 loose-list → W5-T11d.
- K9 normalizeHTML/astToHTML → W1-T26a/b (defined, test-only, parallelizable).
- K10 Task 1 standalone → W0-T1 merges model.

**Major fixes applied:** M1 (W10-T24 test rewrite), M2 tabs (W1-T3), M3 ≤3 indent (W3-Tcont), M4 paragraph interruption (W3-Tcont), M5 def-list details (W3-T15), M6 fence rules (W3-T8), M7 link dest/title (W8-T20b), M8 table escaped pipe + delimiter (W3-T13), M9 GFM autolink punct (W10-T23), M10 paragraph trim (W2-T4), M11 multi-line link-ref (W3-T14wire), M12 normalizeHTML (W1-T26b), M13 footnote multi-paragraph (W3-T14wire).

**Spec coverage:** §1 → W0-T1; §2 → W0-T1; §3 two-pass → W2-T4 (A) + W6-T16b (B); §4 tokenize+stack → W7-T18a/W8-T18c; §5 extended → W3-T13/T15, W5-T12, W3-T14wire, W10-T23/T25; §6 testing → every task TDD + W11-T26d/e; §7 limitations → W11-T27. Success criteria → Global Constraints + W11-T27.

**No forward references between micro-tasks:** every `blockedBy` is explicit; the dependency spine is acyclic; each leaf micro-task compiles and passes independently. The riskiest unit (W8-T18c) is isolated and gated by a rule-of-3 test ladder.

**Standing user rule honored:** hand-written, zero-dependency, TDD — no `swift-markdown`, no external parser. Conformance fixtures are *reference test data*, not a code dependency (the "own parser" rule is intact).