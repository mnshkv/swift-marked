# Markdown Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a hand-written, zero-dependency Markdown parser that turns Markdown text into a value-type AST covering CommonMark + GFM + extended syntax.

**Architecture:** A pure-Swift module `MarkdownAST` with one public entry point, `MarkdownParser.parse(_:) -> MarkdownDocument`. Parsing runs in two passes: Pass A is a line-oriented container/leaf block scanner that also collects link-reference and footnote definitions; Pass B parses each leaf block's raw text into inlines via a CommonMark tokenizer + delimiter-stack resolver. No SwiftUI, no throwing — parsing is total.

**Tech Stack:** Swift 6.2, SwiftPM, Swift Testing (`import Testing`, `@Test`, `#expect`). No external dependencies.

## Global Constraints

- Module name: `MarkdownAST`. No `import SwiftUI`, no external dependencies anywhere in the target.
- Swift tools version: 6.2 (already set in `Package.swift`).
- All AST types are `public`, `Sendable`, `Equatable`, `Hashable`; value types only (no classes).
- `MarkdownParser.parse` never throws and never fails — any `String` yields a valid `MarkdownDocument`.
- TDD only: every behavior starts as a failing Swift Testing test. Commit after each task.
- No source ranges in AST nodes (YAGNI). HTML blocks/inline and character/entity references are out of scope (pass through as literal text).
- Test framework is Swift Testing, NOT XCTest. Use `#expect(...)`, not `XCTAssert`.
- Run build with `swift build`, tests with `swift test`.

---

### Task 1: Package layout & module skeleton

**Files:**
- Modify: `Package.swift`
- Create: `Sources/MarkdownAST/MarkdownParser.swift`
- Test: `Tests/MarkdownASTTests/SmokeTests.swift`
- Delete: `Sources/swiftui-markdown/swiftui_markdown.swift`, `Tests/swiftui-markdownTests/swiftui_markdownTests.swift`

**Interfaces:**
- Produces: `enum MarkdownParser { public static func parse(_ source: String) -> MarkdownDocument }` and `struct MarkdownDocument` (fleshed out in Task 2 — here a minimal empty stub so the module compiles).

- [ ] **Step 1: Rewrite `Package.swift` to declare the `MarkdownAST` target**

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swiftui-markdown",
    products: [
        .library(name: "MarkdownAST", targets: ["MarkdownAST"]),
    ],
    targets: [
        .target(name: "MarkdownAST"),
        .testTarget(
            name: "MarkdownASTTests",
            dependencies: ["MarkdownAST"]
        ),
    ]
)
```

- [ ] **Step 2: Remove the old template sources/tests**

```bash
git rm Sources/swiftui-markdown/swiftui_markdown.swift Tests/swiftui-markdownTests/swiftui_markdownTests.swift
rmdir Sources/swiftui-markdown Tests/swiftui-markdownTests 2>/dev/null || true
```

- [ ] **Step 3: Write a minimal parser + document stub so the module compiles**

`Sources/MarkdownAST/MarkdownParser.swift`:

```swift
/// Parses Markdown (CommonMark + GFM + extended) into a value-type AST.
///
/// Out of scope (passed through as literal text): HTML blocks and inline HTML,
/// character/entity references, nested links, and rare CommonMark corners.
public enum MarkdownParser {
    public static func parse(_ source: String) -> MarkdownDocument {
        MarkdownDocument(blocks: [], footnotes: [])
    }
}

public struct MarkdownDocument: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var footnotes: [FootnoteDefinition]
    public init(blocks: [MarkdownBlock], footnotes: [FootnoteDefinition]) {
        self.blocks = blocks
        self.footnotes = footnotes
    }
}
```

(These types reference `MarkdownBlock`/`FootnoteDefinition` defined in Task 2. Do Task 2's Step 1 file creation together with this step so the module compiles, or temporarily type `blocks: [Int]` — cleanest is to land Task 2 model types in the same commit. For clarity this plan keeps them separate; if compiling between tasks, fold Task 2 Step 1 in here.)

- [ ] **Step 4: Write the smoke test**

`Tests/MarkdownASTTests/SmokeTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func emptyInputProducesEmptyDocument() {
    let doc = MarkdownParser.parse("")
    #expect(doc.blocks.isEmpty)
    #expect(doc.footnotes.isEmpty)
}
```

- [ ] **Step 5: Run tests, expect PASS once Task 2 model lands**

Run: `swift test --filter SmokeTests`
Expected: PASS (after the AST model from Task 2 exists).

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold MarkdownAST module and test target"
```

---

### Task 2: AST model types

**Files:**
- Create: `Sources/MarkdownAST/MarkdownBlock.swift`
- Create: `Sources/MarkdownAST/MarkdownInline.swift`
- Test: `Tests/MarkdownASTTests/ModelTests.swift`

**Interfaces:**
- Produces: `MarkdownBlock`, `MarkdownList`, `MarkdownListItem`, `TaskState`, `MarkdownTable`, `MarkdownDefinition`, `FootnoteDefinition`, `MarkdownInline` — exactly as in the spec. Every later task consumes these.

- [ ] **Step 1: Create block model**

`Sources/MarkdownAST/MarkdownBlock.swift`:

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
    public enum Kind: Equatable, Sendable, Hashable {
        case bullet
        case ordered(start: Int)
    }
    public var kind: Kind
    public var isTight: Bool
    public var items: [MarkdownListItem]
    public init(kind: Kind, isTight: Bool, items: [MarkdownListItem]) {
        self.kind = kind; self.isTight = isTight; self.items = items
    }
}

public struct MarkdownListItem: Equatable, Sendable, Hashable {
    public var blocks: [MarkdownBlock]
    public var task: TaskState?
    public init(blocks: [MarkdownBlock], task: TaskState? = nil) {
        self.blocks = blocks; self.task = task
    }
}

public enum TaskState: Equatable, Sendable, Hashable { case checked, unchecked }

public struct MarkdownTable: Equatable, Sendable, Hashable {
    public enum Alignment: Equatable, Sendable, Hashable { case none, left, center, right }
    public var alignments: [Alignment]
    public var header: [[MarkdownInline]]
    public var rows: [[[MarkdownInline]]]
    public init(alignments: [Alignment], header: [[MarkdownInline]], rows: [[[MarkdownInline]]]) {
        self.alignments = alignments; self.header = header; self.rows = rows
    }
}

public struct MarkdownDefinition: Equatable, Sendable, Hashable {
    public var term: [MarkdownInline]
    public var details: [[MarkdownBlock]]
    public init(term: [MarkdownInline], details: [[MarkdownBlock]]) {
        self.term = term; self.details = details
    }
}

public struct FootnoteDefinition: Equatable, Sendable, Hashable {
    public var id: String
    public var blocks: [MarkdownBlock]
    public init(id: String, blocks: [MarkdownBlock]) {
        self.id = id; self.blocks = blocks
    }
}
```

- [ ] **Step 2: Create inline model**

`Sources/MarkdownAST/MarkdownInline.swift`:

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

- [ ] **Step 3: Write model test (construct & equate)**

`Tests/MarkdownASTTests/ModelTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func blocksAreEquatable() {
    let a = MarkdownBlock.paragraph(content: [.text("hi")])
    let b = MarkdownBlock.paragraph(content: [.text("hi")])
    #expect(a == b)
}

@Test func listModelHoldsItems() {
    let list = MarkdownList(kind: .ordered(start: 1), isTight: true,
                            items: [MarkdownListItem(blocks: [.paragraph(content: [.text("x")])])])
    #expect(list.items.count == 1)
    #expect(list.kind == .ordered(start: 1))
}
```

- [ ] **Step 4: Run tests**

Run: `swift test --filter ModelTests`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add MarkdownAST value-type model"
```

---

### Task 3: Line preprocessing utility

**Files:**
- Create: `Sources/MarkdownAST/Line.swift`
- Test: `Tests/MarkdownASTTests/LineTests.swift`

**Interfaces:**
- Produces: `func splitIntoLines(_ source: String) -> [Substring]` — splits on `\n`, `\r\n`, `\r`; drops the line terminators; a trailing newline does NOT produce a final empty line, but blank lines in the middle are preserved.

- [ ] **Step 1: Write failing test**

`Tests/MarkdownASTTests/LineTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func splitsOnAllLineEndings() {
    #expect(splitIntoLines("a\nb\r\nc\rd").map(String.init) == ["a", "b", "c", "d"])
}

@Test func preservesBlankLinesButNotTrailingNewline() {
    #expect(splitIntoLines("a\n\nb\n").map(String.init) == ["a", "", "b"])
}

@Test func emptyStringIsNoLines() {
    #expect(splitIntoLines("").isEmpty)
}
```

- [ ] **Step 2: Run, expect FAIL** — Run: `swift test --filter LineTests` — Expected: FAIL ("cannot find splitIntoLines").

- [ ] **Step 3: Implement**

`Sources/MarkdownAST/Line.swift`:

```swift
func splitIntoLines(_ source: String) -> [Substring] {
    guard !source.isEmpty else { return [] }
    var lines: [Substring] = []
    var lineStart = source.startIndex
    var i = source.startIndex
    while i < source.endIndex {
        let c = source[i]
        if c == "\n" {
            lines.append(source[lineStart..<i])
            i = source.index(after: i)
            lineStart = i
        } else if c == "\r" {
            lines.append(source[lineStart..<i])
            i = source.index(after: i)
            if i < source.endIndex, source[i] == "\n" { i = source.index(after: i) }
            lineStart = i
        } else {
            i = source.index(after: i)
        }
    }
    if lineStart < source.endIndex { lines.append(source[lineStart..<source.endIndex]) }
    return lines
}
```

- [ ] **Step 4: Run, expect PASS** — Run: `swift test --filter LineTests`.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: line splitting that normalizes line endings"
```

---

### Task 4: Block scanner skeleton + paragraphs

**Files:**
- Create: `Sources/MarkdownAST/BlockParser.swift`
- Modify: `Sources/MarkdownAST/MarkdownParser.swift`
- Test: `Tests/MarkdownASTTests/ParagraphTests.swift`

**Interfaces:**
- Produces: `struct BlockParser { func parse(_ lines: ArraySlice<Substring>) -> [MarkdownBlock] }`. At this task it only emits `.paragraph`. Inline content at this stage is a single `.text(...)` placeholder (Pass B integration arrives in Task 16); store the joined raw text. Later tasks add leaf/container dispatch in `parse`.
- `MarkdownParser.parse` now wires: `splitIntoLines` → `BlockParser().parse(...)`.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/ParagraphTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func singleParagraph() {
    let doc = MarkdownParser.parse("Hello world")
    #expect(doc.blocks == [.paragraph(content: [.text("Hello world")])])
}

@Test func paragraphsSeparatedByBlankLine() {
    let doc = MarkdownParser.parse("first\n\nsecond")
    #expect(doc.blocks == [
        .paragraph(content: [.text("first")]),
        .paragraph(content: [.text("second")]),
    ])
}

@Test func consecutiveLinesJoinIntoOneParagraph() {
    let doc = MarkdownParser.parse("line one\nline two")
    #expect(doc.blocks == [.paragraph(content: [.text("line one\nline two")])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement the scanner skeleton + paragraph accumulation**

`Sources/MarkdownAST/BlockParser.swift`:

```swift
struct BlockParser {
    func parse(_ lines: ArraySlice<Substring>) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [Substring] = []

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            let raw = paragraph.joined(separator: "\n")
            blocks.append(.paragraph(content: [.text(raw)]))
            paragraph.removeAll()
        }

        for line in lines {
            if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        return blocks
    }
}
```

Modify `MarkdownParser.parse`:

```swift
public static func parse(_ source: String) -> MarkdownDocument {
    let lines = splitIntoLines(source)
    let blocks = BlockParser().parse(lines[...])
    return MarkdownDocument(blocks: blocks, footnotes: [])
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: block scanner skeleton with paragraph accumulation"
```

---

### Task 5: ATX headings

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/HeadingTests.swift`

**Interfaces:**
- Consumes: `BlockParser.parse`. Produces no new public symbols; extends leaf dispatch to recognize ATX headings before paragraph accumulation.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/HeadingTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func atxHeadingLevels() {
    #expect(MarkdownParser.parse("# H1").blocks == [.heading(level: 1, content: [.text("H1")])])
    #expect(MarkdownParser.parse("### H3").blocks == [.heading(level: 3, content: [.text("H3")])])
    #expect(MarkdownParser.parse("###### H6").blocks == [.heading(level: 6, content: [.text("H6")])])
}

@Test func atxHeadingClosingHashesStripped() {
    #expect(MarkdownParser.parse("## Title ##").blocks == [.heading(level: 2, content: [.text("Title")])])
}

@Test func sevenHashesIsNotHeading() {
    #expect(MarkdownParser.parse("####### nope").blocks == [.paragraph(content: [.text("####### nope")])])
}

@Test func headingInterruptsParagraph() {
    #expect(MarkdownParser.parse("para\n# H").blocks == [
        .paragraph(content: [.text("para")]),
        .heading(level: 1, content: [.text("H")]),
    ])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement ATX detection**

In `BlockParser.parse`, inside the `for line in lines` loop, replace the `else` branch so leaf constructs are tried before paragraph accumulation. Add a helper and call it first:

```swift
// Add as a method on BlockParser:
func atxHeading(_ line: Substring) -> MarkdownBlock? {
    let trimmed = line.drop(while: { $0 == " " })
    guard trimmed.first == "#" else { return nil }
    let hashes = trimmed.prefix(while: { $0 == "#" })
    let level = hashes.count
    guard (1...6).contains(level) else { return nil }
    let rest = trimmed.dropFirst(level)
    // Require a space (or end of line) after the hashes.
    guard rest.isEmpty || rest.first == " " else { return nil }
    var content = rest.drop(while: { $0 == " " })
    // Strip an optional closing run of '#'.
    while content.last == " " { content = content.dropLast() }
    if content.last == "#" {
        let trailing = content.reversed().prefix(while: { $0 == "#" })
        let before = content.dropLast(trailing.count)
        if before.isEmpty || before.last == " " {
            content = before
            while content.last == " " { content = content.dropLast() }
        }
    }
    return .heading(level: level, content: [.text(String(content))])
}
```

In the loop, change the non-blank branch to:

```swift
} else if let heading = atxHeading(line) {
    flushParagraph()
    blocks.append(heading)
} else {
    paragraph.append(line)
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ATX heading parsing"
```

---

### Task 6: Thematic breaks

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/ThematicBreakTests.swift`

**Interfaces:**
- Consumes/extends `BlockParser.parse` leaf dispatch. Helper `func thematicBreak(_ line: Substring) -> Bool`.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/ThematicBreakTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func thematicBreakVariants() {
    #expect(MarkdownParser.parse("---").blocks == [.thematicBreak])
    #expect(MarkdownParser.parse("***").blocks == [.thematicBreak])
    #expect(MarkdownParser.parse("___").blocks == [.thematicBreak])
    #expect(MarkdownParser.parse("- - -").blocks == [.thematicBreak])
}

@Test func twoCharsIsNotThematicBreak() {
    #expect(MarkdownParser.parse("--").blocks == [.paragraph(content: [.text("--")])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement**

```swift
func thematicBreak(_ line: Substring) -> Bool {
    let stripped = line.filter { $0 != " " && $0 != "\t" }
    guard stripped.count >= 3 else { return false }
    let first = stripped.first!
    guard first == "-" || first == "*" || first == "_" else { return false }
    return stripped.allSatisfy { $0 == first }
}
```

In the loop, add before the heading branch (thematic break must beat setext `---`, handled in Task 7):

```swift
} else if thematicBreak(line) {
    flushParagraph()
    blocks.append(.thematicBreak)
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: thematic break parsing"
```

---

### Task 7: Setext headings

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/SetextHeadingTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. A setext underline (`=`/`-` run) converts the *pending paragraph* into a heading at paragraph-flush time. `-` underline only applies when there is a pending paragraph; otherwise `---` is a thematic break (Task 6 runs first only when no paragraph is open — adjust ordering as below).

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/SetextHeadingTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func setextLevel1And2() {
    #expect(MarkdownParser.parse("Title\n===").blocks == [.heading(level: 1, content: [.text("Title")])])
    #expect(MarkdownParser.parse("Title\n---").blocks == [.heading(level: 2, content: [.text("Title")])])
}

@Test func dashRuleWithoutParagraphIsThematicBreak() {
    #expect(MarkdownParser.parse("---").blocks == [.thematicBreak])
}

@Test func multilineParagraphBecomesSetextHeading() {
    #expect(MarkdownParser.parse("a\nb\n===").blocks == [.heading(level: 1, content: [.text("a\nb")])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement setext handling**

Add a helper:

```swift
func setextLevel(_ line: Substring) -> Int? {
    let t = line.drop(while: { $0 == " " })
    guard let first = t.first, first == "=" || first == "-" else { return nil }
    let run = t.prefix(while: { $0 == first })
    let rest = t.dropFirst(run.count).drop(while: { $0 == " " })
    guard rest.isEmpty else { return nil }
    return first == "=" ? 1 : 2
}
```

In the loop, the FIRST check inside the non-blank handling must be: if a paragraph is pending and this line is a setext underline, convert it. Restructure the per-line body:

```swift
} else if !paragraph.isEmpty, let level = setextLevel(line) {
    let raw = paragraph.joined(separator: "\n")
    paragraph.removeAll()
    blocks.append(.heading(level: level, content: [.text(raw)]))
} else if thematicBreak(line) {
    flushParagraph()
    blocks.append(.thematicBreak)
} else if let heading = atxHeading(line) {
    flushParagraph()
    blocks.append(heading)
} else {
    paragraph.append(line)
}
```

Note ordering: setext check requires a pending paragraph, so `---` alone (no paragraph) correctly falls through to thematic break.

- [ ] **Step 4: Run, expect PASS** (re-run Task 6 tests too: `swift test --filter ThematicBreak`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: setext heading parsing"
```

---

### Task 8: Fenced code blocks

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/FencedCodeTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. Introduces stateful multi-line consumption: when a fence opens, lines are consumed verbatim until the closing fence. Switch the `for line in lines` loop to an index-based `while` loop over an array so multi-line blocks can advance the cursor. Produces `.codeBlock(language:code:)`; language is the info string's first word, or `nil` if empty.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/FencedCodeTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func fencedCodeBacktick() {
    let doc = MarkdownParser.parse("```\nlet x = 1\n```")
    #expect(doc.blocks == [.codeBlock(language: nil, code: "let x = 1")])
}

@Test func fencedCodeWithLanguage() {
    let doc = MarkdownParser.parse("```swift\nlet x = 1\n```")
    #expect(doc.blocks == [.codeBlock(language: "swift", code: "let x = 1")])
}

@Test func tildeFence() {
    let doc = MarkdownParser.parse("~~~\ncode\n~~~")
    #expect(doc.blocks == [.codeBlock(language: nil, code: "code")])
}

@Test func contentIsVerbatimNotParsed() {
    let doc = MarkdownParser.parse("```\n# not a heading\n```")
    #expect(doc.blocks == [.codeBlock(language: nil, code: "# not a heading")])
}

@Test func unclosedFenceRunsToEnd() {
    let doc = MarkdownParser.parse("```\nabc")
    #expect(doc.blocks == [.codeBlock(language: nil, code: "abc")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Convert the loop to index-based and add fence handling**

Refactor `parse` to:

```swift
func parse(_ lines: ArraySlice<Substring>) -> [MarkdownBlock] {
    var blocks: [MarkdownBlock] = []
    var paragraph: [Substring] = []
    func flushParagraph() {
        guard !paragraph.isEmpty else { return }
        blocks.append(.paragraph(content: [.text(paragraph.joined(separator: "\n"))]))
        paragraph.removeAll()
    }

    let arr = Array(lines)
    var i = 0
    while i < arr.count {
        let line = arr[i]
        if let fence = fenceOpener(line) {
            flushParagraph()
            var body: [Substring] = []
            i += 1
            while i < arr.count, !isFenceCloser(arr[i], fence) {
                body.append(arr[i]); i += 1
            }
            if i < arr.count { i += 1 } // consume closing fence
            blocks.append(.codeBlock(language: fence.language, code: body.joined(separator: "\n")))
            continue
        }
        if line.allSatisfy({ $0 == " " || $0 == "\t" }) {
            flushParagraph()
        } else if !paragraph.isEmpty, let level = setextLevel(line) {
            let raw = paragraph.joined(separator: "\n"); paragraph.removeAll()
            blocks.append(.heading(level: level, content: [.text(raw)]))
        } else if thematicBreak(line) {
            flushParagraph(); blocks.append(.thematicBreak)
        } else if let heading = atxHeading(line) {
            flushParagraph(); blocks.append(heading)
        } else {
            paragraph.append(line)
        }
        i += 1
    }
    flushParagraph()
    return blocks
}
```

Add fence helpers:

```swift
struct Fence { let char: Character; let count: Int; let language: String? }

func fenceOpener(_ line: Substring) -> Fence? {
    let t = line.drop(while: { $0 == " " })
    guard let first = t.first, first == "`" || first == "~" else { return nil }
    let run = t.prefix(while: { $0 == first })
    guard run.count >= 3 else { return nil }
    let info = t.dropFirst(run.count).trimmingCharacters(in: .whitespaces)
    // Backtick info strings may not contain backticks (out-of-scope corner: keep simple).
    let language = info.isEmpty ? nil : String(info.split(separator: " ").first ?? "")
    return Fence(char: first, count: run.count, language: language?.isEmpty == true ? nil : language)
}

func isFenceCloser(_ line: Substring, _ fence: Fence) -> Bool {
    let t = line.drop(while: { $0 == " " })
    guard t.allSatisfy({ $0 == fence.char }) else { return false }
    return t.count >= fence.count && !t.isEmpty
}
```

(`trimmingCharacters(in:)` requires `import Foundation` at the top of `BlockParser.swift`.)

- [ ] **Step 4: Run, expect PASS** (re-run prior block tests too: `swift test`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: fenced code block parsing"
```

---

### Task 9: Indented code blocks

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/IndentedCodeTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. A line indented ≥4 spaces (and not continuing a paragraph) starts an indented code block; consecutive such lines (blank lines allowed inside, trimmed at edges) form one block. The first 4 spaces are stripped from each line.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/IndentedCodeTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func indentedCodeBlock() {
    let doc = MarkdownParser.parse("    let x = 1\n    let y = 2")
    #expect(doc.blocks == [.codeBlock(language: nil, code: "let x = 1\nlet y = 2")])
}

@Test func indentedCodeNotAfterParagraph() {
    // An indented line right after a paragraph line is a lazy paragraph continuation, not code.
    let doc = MarkdownParser.parse("text\n    more")
    #expect(doc.blocks == [.paragraph(content: [.text("text\n    more")])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — add before the final `else { paragraph.append(line) }`:

```swift
} else if paragraph.isEmpty, isIndentedCode(line) {
    var body: [Substring] = []
    while i < arr.count, isIndentedCode(arr[i]) || arr[i].allSatisfy({ $0 == " " }) {
        body.append(stripIndent(arr[i])); i += 1
    }
    while body.last?.isEmpty == true { body.removeLast() }
    blocks.append(.codeBlock(language: nil, code: body.joined(separator: "\n")))
    continue
```

Helpers:

```swift
func isIndentedCode(_ line: Substring) -> Bool {
    line.prefix(4).allSatisfy { $0 == " " } && line.count > 4 ? true
        : line.prefix(4) == "    " && !line.dropFirst(4).isEmpty
}

func stripIndent(_ line: Substring) -> Substring {
    line.hasPrefix("    ") ? line.dropFirst(4) : line
}
```

Simplify `isIndentedCode` to: `line.hasPrefix("    ") && !line.dropFirst(4).allSatisfy { $0 == " " }`.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: indented code block parsing"
```

---

### Task 10: Block quotes (nested)

**Files:**
- Create: `Sources/MarkdownAST/Containers.swift`
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/BlockQuoteTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. A run of lines beginning with `>` (optionally one following space) forms a block quote; the marker is stripped and the inner lines are parsed recursively via `BlockParser().parse(...)`, enabling nesting and nested constructs. Lazy continuation: a non-blank, non-marker line directly continuing a quote paragraph stays in the quote.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/BlockQuoteTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func simpleBlockQuote() {
    let doc = MarkdownParser.parse("> hello")
    #expect(doc.blocks == [.blockQuote(blocks: [.paragraph(content: [.text("hello")])])])
}

@Test func nestedBlockQuote() {
    let doc = MarkdownParser.parse("> > deep")
    #expect(doc.blocks == [.blockQuote(blocks: [.blockQuote(blocks: [.paragraph(content: [.text("deep")])])])])
}

@Test func blockQuoteWithHeading() {
    let doc = MarkdownParser.parse("> # H")
    #expect(doc.blocks == [.blockQuote(blocks: [.heading(level: 1, content: [.text("H")])])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — add a block-quote branch near the top of the per-line dispatch (after fence handling, before blank handling):

```swift
if line.drop(while: { $0 == " " }).first == ">" {
    flushParagraph()
    var inner: [Substring] = []
    while i < arr.count {
        let l = arr[i]
        let stripped = l.drop(while: { $0 == " " })
        if stripped.first == ">" {
            var rest = stripped.dropFirst()
            if rest.first == " " { rest = rest.dropFirst() }
            inner.append(rest)
            i += 1
        } else if !stripped.isEmpty {
            inner.append(l) // lazy continuation
            i += 1
        } else {
            break
        }
    }
    blocks.append(.blockQuote(blocks: parse(inner[...])))
    continue
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: nested block quote parsing"
```

---

### Task 11: Lists (bullet & ordered, nested, tight/loose)

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Create: `Sources/MarkdownAST/ListParser.swift`
- Test: `Tests/MarkdownASTTests/ListTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. Produces `.list(MarkdownList)`. Recognizes bullet markers `-`/`+`/`*` and ordered `N.`/`N)`. Item content (including continuation lines indented to the marker width) is parsed recursively via `BlockParser().parse(...)`, giving nesting for free. `isTight` is false if any blank line separates items; ordered `start` is the first item's number.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/ListTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func bulletList() {
    let doc = MarkdownParser.parse("- a\n- b")
    #expect(doc.blocks == [.list(MarkdownList(kind: .bullet, isTight: true, items: [
        MarkdownListItem(blocks: [.paragraph(content: [.text("a")])]),
        MarkdownListItem(blocks: [.paragraph(content: [.text("b")])]),
    ]))])
}

@Test func orderedListStart() {
    let doc = MarkdownParser.parse("3. x\n4. y")
    guard case .list(let list) = doc.blocks[0] else { Issue.record("not a list"); return }
    #expect(list.kind == .ordered(start: 3))
    #expect(list.items.count == 2)
}

@Test func nestedList() {
    let doc = MarkdownParser.parse("- a\n  - b")
    let inner = MarkdownList(kind: .bullet, isTight: true,
        items: [MarkdownListItem(blocks: [.paragraph(content: [.text("b")])])])
    #expect(doc.blocks == [.list(MarkdownList(kind: .bullet, isTight: true, items: [
        MarkdownListItem(blocks: [.paragraph(content: [.text("a")]), .list(inner)]),
    ]))])
}

@Test func looseListWhenBlankBetweenItems() {
    let doc = MarkdownParser.parse("- a\n\n- b")
    guard case .list(let list) = doc.blocks[0] else { Issue.record("not a list"); return }
    #expect(list.isTight == false)
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement list parsing**

`Sources/MarkdownAST/ListParser.swift`:

```swift
import Foundation

struct ListMarker {
    enum Kind: Equatable { case bullet(Character); case ordered(number: Int, delim: Character) }
    let kind: Kind
    let markerWidth: Int   // columns from line start through the space after the marker
}

func listMarker(_ line: Substring) -> ListMarker? {
    let leading = line.prefix(while: { $0 == " " }).count
    guard leading < 4 else { return nil }
    var rest = line.dropFirst(leading)
    guard let first = rest.first else { return nil }
    if first == "-" || first == "+" || first == "*" {
        rest = rest.dropFirst()
        guard rest.first == " " || rest.isEmpty else { return nil }
        let spaces = rest.prefix(while: { $0 == " " }).count
        return ListMarker(kind: .bullet(first), markerWidth: leading + 1 + max(spaces, 1))
    }
    let digits = rest.prefix(while: { $0.isNumber })
    guard !digits.isEmpty, digits.count <= 9, let n = Int(digits) else { return nil }
    let afterDigits = rest.dropFirst(digits.count)
    guard let delim = afterDigits.first, delim == "." || delim == ")" else { return nil }
    let afterDelim = afterDigits.dropFirst()
    guard afterDelim.first == " " || afterDelim.isEmpty else { return nil }
    let spaces = afterDelim.prefix(while: { $0 == " " }).count
    return ListMarker(kind: .ordered(number: n, delim: delim),
                      markerWidth: leading + digits.count + 1 + max(spaces, 1))
}
```

In `BlockParser.parse`, add a list branch (after block quote, before blank handling):

```swift
if let marker = listMarker(line) {
    flushParagraph()
    let (block, consumed) = parseList(arr, from: i, firstMarker: marker)
    blocks.append(block)
    i = consumed
    continue
}
```

Add `parseList` as a method on `BlockParser`:

```swift
func parseList(_ arr: [Substring], from start: Int, firstMarker: ListMarker) -> (MarkdownBlock, Int) {
    func sameKind(_ a: ListMarker.Kind, _ b: ListMarker.Kind) -> Bool {
        switch (a, b) {
        case (.bullet(let x), .bullet(let y)): return x == y
        case (.ordered(_, let x), .ordered(_, let y)): return x == y
        default: return false
        }
    }
    var items: [MarkdownListItem] = []
    var isTight = true
    var i = start
    var sawBlank = false
    let kind: MarkdownList.Kind = {
        if case .ordered(let n, _) = firstMarker.kind { return .ordered(start: n) }
        return .bullet
    }()

    while i < arr.count {
        guard let m = listMarker(arr[i]), sameKind(m.kind, firstMarker.kind) else {
            if arr[i].allSatisfy({ $0 == " " }) { sawBlank = true; i += 1; continue }
            break
        }
        if sawBlank { isTight = false; sawBlank = false }
        // Collect this item's lines: the marker line's remainder + following lines
        // indented at least markerWidth.
        var itemLines: [Substring] = [arr[i].dropFirst(m.markerWidth)]
        i += 1
        while i < arr.count {
            let l = arr[i]
            if l.allSatisfy({ $0 == " " }) { itemLines.append(""); i += 1; continue }
            if listMarker(l) != nil, l.prefix(while: { $0 == " " }).count < m.markerWidth { break }
            if l.prefix(m.markerWidth).allSatisfy({ $0 == " " }) {
                itemLines.append(l.dropFirst(m.markerWidth)); i += 1
            } else if listMarker(l) == nil {
                itemLines.append(l); i += 1 // lazy continuation
            } else { break }
        }
        while itemLines.last?.isEmpty == true { itemLines.removeLast(); isTight = isTight && true }
        items.append(MarkdownListItem(blocks: parse(itemLines[...])))
    }
    return (.list(MarkdownList(kind: kind, isTight: isTight, items: items)), i)
}
```

- [ ] **Step 4: Run, expect PASS** (run full suite: `swift test`).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: ordered/unordered/nested list parsing with tight-loose"
```

---

### Task 12: GFM task list items

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/TaskListTests.swift`

**Interfaces:**
- Consumes list parsing. After an item's blocks are parsed, if the item's first inline text begins with `[ ]`/`[x]`/`[X]`, set `item.task` and strip the marker from the text.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/TaskListTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func uncheckedTask() {
    let doc = MarkdownParser.parse("- [ ] todo")
    guard case .list(let list) = doc.blocks[0] else { Issue.record("not list"); return }
    #expect(list.items[0].task == .unchecked)
    #expect(list.items[0].blocks == [.paragraph(content: [.text("todo")])])
}

@Test func checkedTask() {
    let doc = MarkdownParser.parse("- [x] done")
    guard case .list(let list) = doc.blocks[0] else { Issue.record("not list"); return }
    #expect(list.items[0].task == .checked)
    #expect(list.items[0].blocks == [.paragraph(content: [.text("done")])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — replace the `items.append(...)` line in `parseList` with:

```swift
var itemBlocks = parse(itemLines[...])
var task: TaskState? = nil
if case .paragraph(let content)? = itemBlocks.first,
   case .text(let s)? = content.first {
    if s.hasPrefix("[ ] ") || s == "[ ]" {
        task = .unchecked
        itemBlocks[0] = .paragraph(content: replaceFirstText(content, dropping: 3))
    } else if s.hasPrefix("[x] ") || s.hasPrefix("[X] ") || s == "[x]" || s == "[X]" {
        task = .checked
        itemBlocks[0] = .paragraph(content: replaceFirstText(content, dropping: 3))
    }
}
items.append(MarkdownListItem(blocks: itemBlocks, task: task))
```

Helper on `BlockParser`:

```swift
func replaceFirstText(_ content: [MarkdownInline], dropping prefixCount: Int) -> [MarkdownInline] {
    guard case .text(let s)? = content.first else { return content }
    let trimmed = String(s.dropFirst(prefixCount)).drop(while: { $0 == " " })
    var copy = content
    copy[0] = .text(String(trimmed))
    return copy
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: GFM task list items"
```

---

### Task 13: GFM tables

**Files:**
- Create: `Sources/MarkdownAST/TableParser.swift`
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/TableTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. A line that, together with the NEXT line being a valid delimiter row (`| --- | :-: |`), forms a table. Produces `.table(MarkdownTable)`. Cell raw text stored as a single `.text(...)` (inline parsing happens in Pass B). Cell count normalized to header width.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/TableTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func simpleTable() {
    let doc = MarkdownParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
    #expect(doc.blocks == [.table(MarkdownTable(
        alignments: [.none, .none],
        header: [[.text("A")], [.text("B")]],
        rows: [[[.text("1")], [.text("2")]]]
    ))])
}

@Test func tableAlignments() {
    let doc = MarkdownParser.parse("| L | C | R |\n| :-- | :-: | --: |\n| 1 | 2 | 3 |")
    guard case .table(let t) = doc.blocks[0] else { Issue.record("not table"); return }
    #expect(t.alignments == [.left, .center, .right])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement table parsing**

`Sources/MarkdownAST/TableParser.swift`:

```swift
func splitTableRow(_ line: Substring) -> [String] {
    var s = line.trimmingCharacters(in: .whitespaces)[...]
    if s.first == "|" { s = s.dropFirst() }
    if s.last == "|" { s = s.dropLast() }
    var cells: [String] = []
    var current = ""
    var escaped = false
    for ch in s {
        if escaped { current.append(ch); escaped = false }
        else if ch == "\\" { escaped = true; current.append(ch) }
        else if ch == "|" { cells.append(current.trimmingCharacters(in: .whitespaces)); current = "" }
        else { current.append(ch) }
    }
    cells.append(current.trimmingCharacters(in: .whitespaces))
    return cells
}

func delimiterAlignments(_ line: Substring) -> [MarkdownTable.Alignment]? {
    let cells = splitTableRow(line)
    guard !cells.isEmpty else { return nil }
    var result: [MarkdownTable.Alignment] = []
    for cell in cells {
        let c = cell.trimmingCharacters(in: .whitespaces)
        guard c.allSatisfy({ $0 == "-" || $0 == ":" }), c.contains("-") else { return nil }
        let left = c.hasPrefix(":"), right = c.hasSuffix(":")
        result.append(left && right ? .center : right ? .right : left ? .left : .none)
    }
    return result
}
```

(`TableParser.swift` needs `import Foundation`.)

In `BlockParser.parse`, add (before blank handling, requires lookahead at `arr[i+1]`):

```swift
if i + 1 < arr.count, line.contains("|"),
   let aligns = delimiterAlignments(arr[i + 1]) {
    let headerCells = splitTableRow(line)
    if headerCells.count == aligns.count {
        flushParagraph()
        let header = headerCells.map { [MarkdownInline.text($0)] }
        var rows: [[[MarkdownInline]]] = []
        i += 2
        while i < arr.count, arr[i].contains("|"), !arr[i].allSatisfy({ $0 == " " }) {
            var cells = splitTableRow(arr[i]).map { [MarkdownInline.text($0)] }
            if cells.count < aligns.count { cells += Array(repeating: [.text("")], count: aligns.count - cells.count) }
            if cells.count > aligns.count { cells = Array(cells.prefix(aligns.count)) }
            rows.append(cells); i += 1
        }
        blocks.append(.table(MarkdownTable(alignments: aligns, header: header, rows: rows)))
        continue
    }
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: GFM table parsing"
```

---

### Task 14: Link reference & footnote definition collection

**Files:**
- Create: `Sources/MarkdownAST/DefinitionStore.swift`
- Modify: `Sources/MarkdownAST/MarkdownParser.swift`, `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/DefinitionTests.swift`

**Interfaces:**
- Produces: `struct DefinitionStore { var links: [String: (destination: String, title: String?)]; var footnotes: [FootnoteDefinition] }` with normalized (case-folded, whitespace-collapsed) link labels. `BlockParser` is initialized with an `inout DefinitionStore` (a reference-semantics box) so it can register definitions found anywhere, including nested. Recommended: make `DefinitionStore` a `final class` for shared mutation across recursive `parse` calls.
- `MarkdownParser.parse` runs Pass A (collect), making the store available to Pass B (Task 22+).

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/DefinitionTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func linkReferenceDefinitionIsCollectedAndRemoved() {
    // The definition line should not appear as a paragraph.
    let doc = MarkdownParser.parse("[id]: https://example.com \"T\"")
    #expect(doc.blocks.isEmpty)
}

@Test func footnoteDefinitionIsCollected() {
    let doc = MarkdownParser.parse("[^1]: a footnote")
    #expect(doc.blocks.isEmpty)
    #expect(doc.footnotes == [FootnoteDefinition(id: "1", blocks: [.paragraph(content: [.text("a footnote")])])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement the store + collection**

`Sources/MarkdownAST/DefinitionStore.swift`:

```swift
import Foundation

final class DefinitionStore {
    struct LinkDef { let destination: String; let title: String? }
    private(set) var links: [String: LinkDef] = [:]
    private(set) var footnotes: [FootnoteDefinition] = []

    static func normalize(_ label: String) -> String {
        label.trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: { $0 == " " || $0 == "\t" || $0 == "\n" })
            .joined(separator: " ")
    }

    func addLink(label: String, destination: String, title: String?) {
        let key = Self.normalize(label)
        if links[key] == nil { links[key] = LinkDef(destination: destination, title: title) }
    }
    func link(for label: String) -> LinkDef? { links[Self.normalize(label)] }
    func addFootnote(_ def: FootnoteDefinition) { footnotes.append(def) }
}
```

Add a parser for a leading link-reference-definition and footnote-definition. In `BlockParser`, give the struct a `let defs: DefinitionStore` stored property and an initializer `init(defs: DefinitionStore)`. In the per-line dispatch, before paragraph accumulation:

```swift
if let fn = footnoteDefinition(arr, from: i) {
    flushParagraph()
    defs.addFootnote(FootnoteDefinition(id: fn.id, blocks: parse(fn.bodyLines[...])))
    i = fn.consumed
    continue
}
if !paragraph.isEmpty == false, let def = linkReferenceDefinition(line) {
    defs.addLink(label: def.label, destination: def.destination, title: def.title)
    i += 1
    continue
}
```

Helpers (in `DefinitionStore.swift` or `BlockParser.swift`):

```swift
func linkReferenceDefinition(_ line: Substring) -> (label: String, destination: String, title: String?)? {
    let t = line.drop(while: { $0 == " " })
    guard t.first == "[" else { return nil }
    guard let close = t.firstIndex(of: "]") else { return nil }
    let label = String(t[t.index(after: t.startIndex)..<close])
    guard label.first != "^" else { return nil } // that's a footnote def
    var rest = t[t.index(after: close)...]
    guard rest.first == ":" else { return nil }
    rest = rest.dropFirst().drop(while: { $0 == " " })
    guard !rest.isEmpty else { return nil }
    // destination then optional title in quotes
    let dest = rest.prefix(while: { $0 != " " })
    let after = rest.dropFirst(dest.count).drop(while: { $0 == " " })
    var title: String? = nil
    if let q = after.first, q == "\"" || q == "'" {
        let body = after.dropFirst()
        if let end = body.firstIndex(of: q) { title = String(body[..<end]) }
    }
    return (label, String(dest), title)
}

func footnoteDefinition(_ arr: [Substring], from start: Int)
    -> (id: String, bodyLines: [Substring], consumed: Int)? {
    let line = arr[start]
    let t = line.drop(while: { $0 == " " })
    guard t.hasPrefix("[^"), let close = t.firstIndex(of: "]") else { return nil }
    let id = String(t[t.index(t.startIndex, offsetBy: 2)..<close])
    guard !id.isEmpty, t[t.index(after: close)...].first == ":" else { return nil }
    let firstBody = t[t.index(t.startIndex, offsetBy: t.distance(from: t.startIndex, to: close) + 2)...]
        .drop(while: { $0 == " " })
    var body: [Substring] = [firstBody]
    var i = start + 1
    while i < arr.count, arr[i].hasPrefix("    ") || arr[i].allSatisfy({ $0 == " " }) {
        if arr[i].allSatisfy({ $0 == " " }) { break }
        body.append(arr[i].dropFirst(4)); i += 1
    }
    return (id, body, i)
}
```

Update `MarkdownParser.parse`:

```swift
public static func parse(_ source: String) -> MarkdownDocument {
    let lines = splitIntoLines(source)
    let defs = DefinitionStore()
    let blocks = BlockParser(defs: defs).parse(lines[...])
    return MarkdownDocument(blocks: blocks, footnotes: defs.footnotes)
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: collect link reference and footnote definitions"
```

---

### Task 15: Definition lists

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift`
- Test: `Tests/MarkdownASTTests/DefinitionListTests.swift`

**Interfaces:**
- Consumes `BlockParser.parse`. A term line immediately followed by one or more `: detail` lines becomes `.definitionList([MarkdownDefinition])`. Consecutive term/detail groups merge into one definition list.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/DefinitionListTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func simpleDefinitionList() {
    let doc = MarkdownParser.parse("Term\n: Definition")
    #expect(doc.blocks == [.definitionList([
        MarkdownDefinition(term: [.text("Term")], details: [[.paragraph(content: [.text("Definition")])]])
    ])])
}

@Test func multipleDefinitions() {
    let doc = MarkdownParser.parse("A\n: one\nB\n: two")
    guard case .definitionList(let defs) = doc.blocks[0] else { Issue.record("not deflist"); return }
    #expect(defs.count == 2)
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — when about to flush a paragraph because the NEXT line is `: ...`, build a definition instead. Add, near setext handling (a term is a single pending paragraph line, next line begins with `: `):

```swift
if i + 1 < arr.count, !paragraph.isEmpty,
   arr[i + 1].drop(while: { $0 == " " }).first == ":" {
    // current `line` already appended? Ensure term = paragraph buffer (the term line).
}
```

Simpler approach — handle at the top of dispatch when the current line is a `: detail` and there is a one-line pending paragraph (the term):

```swift
if line.drop(while: { $0 == " " }).first == ":",
   paragraph.count >= 1 {
    let term = paragraph.joined(separator: "\n")
    paragraph.removeAll()
    var detailLines: [Substring] = [line.drop(while: { $0 == " " }).dropFirst().drop(while: { $0 == " " })]
    i += 1
    while i < arr.count, arr[i].drop(while: { $0 == " " }).first == ":" {
        detailLines.append(arr[i].drop(while: { $0 == " " }).dropFirst().drop(while: { $0 == " " }))
        i += 1
    }
    let definition = MarkdownDefinition(term: [.text(term)], details: [parse(detailLines[...])])
    if case .definitionList(var defs)? = blocks.last {
        defs.append(definition); blocks[blocks.count - 1] = .definitionList(defs)
    } else {
        blocks.append(.definitionList([definition]))
    }
    continue
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: definition list parsing"
```

---

### Task 16: Inline parser scaffold — text, escapes, Pass B integration

**Files:**
- Create: `Sources/MarkdownAST/InlineParser.swift`
- Modify: `Sources/MarkdownAST/BlockParser.swift` (replace placeholder `.text(raw)` with `InlineParser` calls)
- Test: `Tests/MarkdownASTTests/InlineTextTests.swift`

**Interfaces:**
- Produces: `struct InlineParser { let defs: DefinitionStore; func parse(_ text: String) -> [MarkdownInline] }`. Now every place in `BlockParser` that built `[.text(raw)]` calls `inline.parse(raw)` where `inline = InlineParser(defs: defs)`: paragraph content, heading content, table cells, definition terms. At this task `InlineParser.parse` handles plain text and backslash escapes only; later tasks extend it.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/InlineTextTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func plainText() {
    #expect(inlines("just text") == [.text("just text")])
}

@Test func backslashEscape() {
    #expect(inlines("\\*not emphasis\\*") == [.text("*not emphasis*")])
}

@Test func backslashBeforeNormalCharKept() {
    #expect(inlines("a\\b") == [.text("a\\b")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement scaffold**

`Sources/MarkdownAST/InlineParser.swift`:

```swift
struct InlineParser {
    let defs: DefinitionStore

    private static let escapable: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    func parse(_ text: String) -> [MarkdownInline] {
        var result = ""
        let chars = Array(text)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, Self.escapable.contains(chars[i + 1]) {
                result.append(chars[i + 1]); i += 2; continue
            }
            result.append(c); i += 1
        }
        return result.isEmpty ? [] : [.text(result)]
    }
}
```

In `BlockParser`, wherever content was `[.text(raw)]`, call `InlineParser(defs: defs).parse(raw)`. Update: paragraph flush, ATX heading, setext heading, table header/rows/cells, definition term. (Lists/quotes inherit via recursive `parse`, which calls these.)

- [ ] **Step 4: Run, expect PASS** (run full suite — adjust earlier tests only if they asserted raw `.text` that escapes would change; none should).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: inline parser scaffold with backslash escapes; wire Pass B"
```

---

### Task 17: Inline code spans

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/CodeSpanTests.swift`

**Interfaces:**
- Extends `InlineParser.parse`. Code spans use matched backtick runs of equal length; a single leading/trailing space inside is stripped when content is non-blank. Backslashes inside code spans are literal.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/CodeSpanTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func simpleCodeSpan() {
    #expect(inlines("a `code` b") == [.text("a "), .code("code"), .text(" b")])
}

@Test func doubleBacktickAllowsBacktickInside() {
    #expect(inlines("``a`b``") == [.code("a`b")])
}

@Test func codeSpanContentNotEscaped() {
    #expect(inlines("`\\*`") == [.code("\\*")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — restructure `parse` into a tokenized scan. Replace the body so backtick runs are detected first (higher precedence than escapes outside code). Implementation:

```swift
func parse(_ text: String) -> [MarkdownInline] {
    let chars = Array(text)
    var nodes: [MarkdownInline] = []
    var buffer = ""
    func flush() { if !buffer.isEmpty { nodes.append(.text(buffer)); buffer = "" } }

    var i = 0
    while i < chars.count {
        let c = chars[i]
        if c == "`" {
            let run = backtickRunLength(chars, at: i)
            if let close = findClosingBackticks(chars, openEnd: i + run, length: run) {
                flush()
                var content = String(chars[(i + run)..<close])
                if content.first == " ", content.last == " ", content.contains(where: { $0 != " " }) {
                    content = String(content.dropFirst().dropLast())
                }
                nodes.append(.code(content))
                i = close + run
                continue
            }
        }
        if c == "\\", i + 1 < chars.count, Self.escapable.contains(chars[i + 1]) {
            buffer.append(chars[i + 1]); i += 2; continue
        }
        buffer.append(c); i += 1
    }
    flush()
    return nodes
}

private func backtickRunLength(_ chars: [Character], at i: Int) -> Int {
    var n = 0; var j = i
    while j < chars.count, chars[j] == "`" { n += 1; j += 1 }
    return n
}

private func findClosingBackticks(_ chars: [Character], openEnd: Int, length: Int) -> Int? {
    var j = openEnd
    while j < chars.count {
        if chars[j] == "`" {
            let run = backtickRunLength(chars, at: j)
            if run == length { return j }
            j += run
        } else { j += 1 }
    }
    return nil
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: inline code spans"
```

---

### Task 18: Emphasis & strong (delimiter stack, flanking, rule of 3)

**Files:**
- Create: `Sources/MarkdownAST/EmphasisResolver.swift`
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/EmphasisTests.swift`

**Interfaces:**
- Produces: the CommonMark delimiter-stack algorithm operating over an intermediate token list. `InlineParser.parse` now: (1) tokenizes into a list of nodes where `*`/`_` runs become delimiter tokens, code spans/text become literal nodes; (2) runs `resolveEmphasis` which pairs delimiters producing `.emphasis`/`.strong`. This task introduces an internal token type; keep code spans from Task 17 as already-resolved nodes that the resolver passes through untouched.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/EmphasisTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func simpleEmphasis() {
    #expect(inlines("*hi*") == [.emphasis([.text("hi")])])
    #expect(inlines("_hi_") == [.emphasis([.text("hi")])])
}

@Test func strong() {
    #expect(inlines("**hi**") == [.strong([.text("hi")])])
}

@Test func strongInsideEmphasis() {
    #expect(inlines("*a **b** c*") == [.emphasis([.text("a "), .strong([.text("b")]), .text(" c")])])
}

@Test func intrawordUnderscoreNotEmphasis() {
    #expect(inlines("a_b_c") == [.text("a_b_c")])
}

@Test func unmatchedStarIsLiteral() {
    #expect(inlines("a * b") == [.text("a * b")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement the delimiter stack**

`Sources/MarkdownAST/EmphasisResolver.swift` — define the token model and resolver:

```swift
enum InlineToken {
    case literal(MarkdownInline)              // text/code/link/etc. already resolved
    case delimiter(char: Character, count: Int, canOpen: Bool, canClose: Bool, text: String)
}

func classifyFlanking(before: Character?, after: Character?) -> (left: Bool, right: Bool) {
    func isWhitespaceOrNil(_ c: Character?) -> Bool { c == nil || c!.isWhitespace }
    func isPunctuation(_ c: Character?) -> Bool { guard let c else { return false }; return c.isPunctuation || c.isSymbol }
    let beforeWS = isWhitespaceOrNil(before), afterWS = isWhitespaceOrNil(after)
    let beforeP = isPunctuation(before), afterP = isPunctuation(after)
    let leftFlanking = !afterWS && (!afterP || beforeWS || beforeP)
    let rightFlanking = !beforeWS && (!beforeP || afterWS || afterP)
    return (leftFlanking, rightFlanking)
}

func resolveEmphasis(_ tokens: [InlineToken]) -> [MarkdownInline] {
    // Standard CommonMark process_emphasis over a doubly-indexed array.
    var tokens = tokens
    var openers: [Int] = []   // indices into tokens that are still-open delimiters

    func emit(range: Range<Int>) -> [MarkdownInline] {
        var out: [MarkdownInline] = []
        for idx in range {
            switch tokens[idx] {
            case .literal(let n): out.append(n)
            case .delimiter(let char, let count, _, _, _):
                if count > 0 { out.append(.text(String(repeating: char, count: count))) }
            }
        }
        return out
    }

    var i = 0
    while i < tokens.count {
        guard case .delimiter(let char, _, _, let canClose, _) = tokens[i], canClose else {
            if case .delimiter = tokens[i] { openers.append(i) }
            i += 1; continue
        }
        // find matching opener of same char with canOpen
        var openerPos: Int? = nil
        for j in openers.reversed() {
            if case .delimiter(let oc, let ocount, let canOpen, _, _) = tokens[j],
               oc == char, canOpen, ocount > 0 {
                // rule of 3: if either is both open&close, sum % 3 == 0 only when each %3==0
                openerPos = j; break
            }
        }
        guard let op = openerPos,
              case .delimiter(let oc, var ocount, let oOpen, let oClose, let otext) = tokens[op],
              case .delimiter(let cc, var ccount, let cOpen, let cClose, let ctext) = tokens[i]
        else { openers.append(i); i += 1; continue }

        let useStrong = ocount >= 2 && ccount >= 2
        let used = useStrong ? 2 : 1
        let inner = emit(range: (op + 1)..<i)
        let node: MarkdownInline = useStrong ? .strong(inner) : .emphasis(inner)

        ocount -= used; ccount -= used
        tokens[op] = .delimiter(char: oc, count: ocount, canOpen: oOpen, canClose: oClose, text: otext)
        tokens[i] = .delimiter(char: cc, count: ccount, canOpen: cOpen, canClose: cClose, text: ctext)
        // replace the inner range + consumed delimiters with the node
        tokens.replaceSubrange((op + 1)...i, with: [.literal(node)] + (ccount > 0 ? [tokens[i]] : []))
        openers.removeAll { $0 > op }
        i = op + 1
        if ocount == 0 { openers.removeAll { $0 == op } }
    }
    return emit(range: 0..<tokens.count)
}
```

> Implementation note for the engineer: the snippet above is the structure; the exact index bookkeeping for `replaceSubrange` is fiddly. Drive it with the tests in Step 1 plus these incremental cases, adding one `#expect` at a time until green: `*a*`, `**a**`, `***a***`, `*a**b**c*`, `**a*b*c**`. If the array-rewrite approach fights you, switch to the canonical CommonMark linked-list `process_emphasis` (openers_bottom per delimiter type, rule of 3: a pairing is forbidden when one delimiter can both open and close and `(openerCount + closerCount) % 3 == 0` while neither count % 3 == 0). Keep the public behavior identical to the tests.

In `InlineParser.parse`, build `[InlineToken]` (delimiter runs for `*`/`_` with flanking from neighboring chars; code spans and text as `.literal`), then `return resolveEmphasis(tokens)`.

- [ ] **Step 4: Run, expect PASS** (iterate per the note until all emphasis tests pass).

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: emphasis/strong via CommonMark delimiter stack"
```

---

### Task 19: Strikethrough (GFM)

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`, `Sources/MarkdownAST/EmphasisResolver.swift`
- Test: `Tests/MarkdownASTTests/StrikethroughTests.swift`

**Interfaces:**
- Extends tokenization to treat `~~` runs as delimiters and the resolver to pair them into `.strikethrough`.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/StrikethroughTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func strikethrough() {
    #expect(inlines("~~gone~~") == [.strikethrough([.text("gone")])])
}

@Test func singleTildeIsLiteral() {
    #expect(inlines("a ~ b") == [.text("a ~ b")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in tokenization, recognize `~` runs of length ≥2 as delimiters with char `~`. In `resolveEmphasis`, when pairing `~` delimiters require both sides count ≥2 and produce `.strikethrough(inner)` consuming 2 each. Add a branch in the node-construction: `let node: MarkdownInline = char == "~" ? .strikethrough(inner) : (useStrong ? .strong(inner) : .emphasis(inner))` and for `~` always treat as the 2-consume case.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: GFM strikethrough"
```

---

### Task 20: Inline links & images

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Create: `Sources/MarkdownAST/LinkParser.swift`
- Test: `Tests/MarkdownASTTests/LinkTests.swift`

**Interfaces:**
- Produces helper `parseInlineLink(chars:from:) -> (node: MarkdownInline, end: Int)?` handling `[text](dest "title")` and `![alt](src "title")` with balanced brackets/parens and optional title. Link text is parsed recursively via `InlineParser.parse`. Links take precedence over emphasis: tokenize links/images into `.literal` nodes before emphasis resolution.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/LinkTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func inlineLink() {
    #expect(inlines("[Swift](https://swift.org)") ==
        [.link(destination: "https://swift.org", title: nil, content: [.text("Swift")])])
}

@Test func inlineLinkWithTitle() {
    #expect(inlines("[x](https://a.com \"T\")") ==
        [.link(destination: "https://a.com", title: "T", content: [.text("x")])])
}

@Test func inlineImage() {
    #expect(inlines("![alt](img.png)") ==
        [.image(source: "img.png", title: nil, alt: "alt")])
}

@Test func emphasisInsideLinkText() {
    #expect(inlines("[*hi*](u)") ==
        [.link(destination: "u", title: nil, content: [.emphasis([.text("hi")])])])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement link parsing**

`Sources/MarkdownAST/LinkParser.swift`:

```swift
extension InlineParser {
    /// Parses an inline link/image starting at `start` (where `chars[start] == "["`,
    /// or `"!"` for image). Returns the node and the index just past the closing `)`.
    func parseInlineLinkOrImage(_ chars: [Character], from start: Int) -> (MarkdownInline, Int)? {
        var i = start
        let isImage = chars[i] == "!"
        if isImage { i += 1 }
        guard i < chars.count, chars[i] == "[" else { return nil }
        guard let closeBracket = matchBracket(chars, openAt: i) else { return nil }
        let textChars = Array(chars[(i + 1)..<closeBracket])
        var j = closeBracket + 1
        guard j < chars.count, chars[j] == "(" else { return nil }
        guard let closeParen = matchParen(chars, openAt: j) else { return nil }
        let inside = Array(chars[(j + 1)..<closeParen]).map(String.init).joined()
        let (dest, title) = splitDestinationAndTitle(inside)
        let end = closeParen + 1
        if isImage {
            return (.image(source: dest, title: title, alt: String(textChars)), end)
        } else {
            return (.link(destination: dest, title: title, content: parse(String(textChars))), end)
        }
    }
}

func matchBracket(_ chars: [Character], openAt: Int) -> Int? {
    var depth = 0
    var i = openAt
    while i < chars.count {
        if chars[i] == "\\" { i += 2; continue }
        if chars[i] == "[" { depth += 1 }
        else if chars[i] == "]" { depth -= 1; if depth == 0 { return i } }
        i += 1
    }
    return nil
}

func matchParen(_ chars: [Character], openAt: Int) -> Int? {
    var depth = 0
    var i = openAt
    while i < chars.count {
        if chars[i] == "\\" { i += 2; continue }
        if chars[i] == "(" { depth += 1 }
        else if chars[i] == ")" { depth -= 1; if depth == 0 { return i } }
        i += 1
    }
    return nil
}

func splitDestinationAndTitle(_ s: String) -> (String, String?) {
    var str = s.trimmingCharacters(in: .whitespaces)
    if str.hasPrefix("<"), let close = str.firstIndex(of: ">") {
        let dest = String(str[str.index(after: str.startIndex)..<close])
        let rest = str[str.index(after: close)...].trimmingCharacters(in: .whitespaces)
        return (dest, extractTitle(rest))
    }
    if let spaceIdx = str.firstIndex(where: { $0 == " " }) {
        let dest = String(str[..<spaceIdx])
        let rest = String(str[str.index(after: spaceIdx)...]).trimmingCharacters(in: .whitespaces)
        return (dest, extractTitle(rest))
    }
    return (str, nil)
}

func extractTitle(_ s: String) -> String? {
    guard let q = s.first, q == "\"" || q == "'" || q == "(" else { return s.isEmpty ? nil : nil }
    let endChar: Character = q == "(" ? ")" : q
    let body = s.dropFirst()
    if let end = body.firstIndex(of: endChar) { return String(body[..<end]) }
    return nil
}
```

(`LinkParser.swift` needs `import Foundation`.)

In `InlineParser.parse` tokenization loop, before treating `[` or `!` as text, attempt `parseInlineLinkOrImage`; on success push `.literal(node)` and advance.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: inline links and images"
```

---

### Task 21: Reference links & images

**Files:**
- Modify: `Sources/MarkdownAST/LinkParser.swift`, `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/ReferenceLinkTests.swift`

**Interfaces:**
- Extends link parsing: `[text][label]`, `[text][]`, and shortcut `[label]` resolve against `defs.link(for:)`. Unresolved references stay literal text.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/ReferenceLinkTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func fullReferenceLink() {
    #expect(inlines("[Swift][sw]\n\n[sw]: https://swift.org") ==
        [.link(destination: "https://swift.org", title: nil, content: [.text("Swift")])])
}

@Test func collapsedReference() {
    #expect(inlines("[sw][]\n\n[sw]: https://swift.org") ==
        [.link(destination: "https://swift.org", title: nil, content: [.text("sw")])])
}

@Test func shortcutReference() {
    #expect(inlines("[sw]\n\n[sw]: https://swift.org") ==
        [.link(destination: "https://swift.org", title: nil, content: [.text("sw")])])
}

@Test func unresolvedReferenceIsLiteral() {
    #expect(inlines("[missing]") == [.text("[missing]")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — extend `parseInlineLinkOrImage`: after `closeBracket`, if next char is not `(`, check for `[label]` (full/collapsed) or shortcut. Resolve via `defs.link(for: label)`; build `.link`/`.image` from the def's destination/title with content = parsed text (or the label text for shortcut). Return `nil` (literal) if unresolved.

```swift
// after computing closeBracket and textChars, before the "(" branch:
var j = closeBracket + 1
if j >= chars.count || chars[j] != "(" {
    // reference forms
    var label = String(textChars)
    if j < chars.count, chars[j] == "[" {
        guard let close2 = matchBracket(chars, openAt: j) else { return nil }
        let explicit = String(chars[(j + 1)..<close2])
        if !explicit.isEmpty { label = explicit }
        j = close2 + 1
    }
    guard let def = defs.link(for: label) else { return nil }
    if isImage { return (.image(source: def.destination, title: def.title, alt: String(textChars)), j) }
    return (.link(destination: def.destination, title: def.title, content: parse(String(textChars))), j)
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: reference links and images"
```

---

### Task 22: CommonMark autolinks

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/AutolinkTests.swift`

**Interfaces:**
- Extends tokenization: `<scheme:...>` and `<email@host>` become `.autolink`. Produces `.autolink(url:)`.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/AutolinkTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func uriAutolink() {
    #expect(inlines("<https://swift.org>") == [.autolink(url: "https://swift.org")])
}

@Test func emailAutolink() {
    #expect(inlines("<a@b.com>") == [.autolink(url: "a@b.com")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in tokenization, on `<`, scan to `>`; if the inner text matches a URI scheme (`^[a-zA-Z][a-zA-Z0-9+.-]*:`) or a simple email (`^[^@\s]+@[^@\s]+\.[^@\s]+$`), emit `.literal(.autolink(url: inner))`. Otherwise treat `<` as literal text.

```swift
if c == "<", let close = indexOf(chars, ">", from: i + 1) {
    let inner = String(chars[(i + 1)..<close])
    if isURIAutolink(inner) || isEmailAutolink(inner) {
        flush(); nodes.append(.literal(.autolink(url: inner))) // or .autolink for non-token builds
        i = close + 1; continue
    }
}
```

Helpers (use simple character scans, no `NSRegularExpression` needed):

```swift
func isURIAutolink(_ s: String) -> Bool {
    guard let colon = s.firstIndex(of: ":") else { return false }
    let scheme = s[..<colon]
    guard let f = scheme.first, f.isLetter else { return false }
    return scheme.allSatisfy { $0.isLetter || $0.isNumber || $0 == "+" || $0 == "." || $0 == "-" }
        && !s[s.index(after: colon)...].contains(where: { $0 == " " || $0 == "<" || $0 == ">" })
}

func isEmailAutolink(_ s: String) -> Bool {
    let parts = s.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return false }
    return !s.contains(where: { $0 == " " })
}
```

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: CommonMark autolinks"
```

---

### Task 23: GFM extended autolinks (bare URLs & emails)

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/ExtendedAutolinkTests.swift`

**Interfaces:**
- Extends tokenization: bare `http://`/`https://`/`www.` runs and bare emails in text become `.autolink`. Trailing punctuation (`.`, `,`, `)`, `!`) is excluded from the link.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/ExtendedAutolinkTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func bareHttpsAutolink() {
    #expect(inlines("see https://swift.org now") ==
        [.text("see "), .autolink(url: "https://swift.org"), .text(" now")])
}

@Test func bareWwwAutolink() {
    #expect(inlines("at www.swift.org.") ==
        [.text("at "), .autolink(url: "www.swift.org"), .text(".")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — at a word boundary in text scanning, detect `http://`, `https://`, or `www.` prefixes; consume URL characters; strip trailing `.,!?)` from the captured URL (returning them to the buffer). Emit `.autolink`. Keep this in the same tokenization loop, checked when starting a new run of non-special chars.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: GFM extended bare autolinks"
```

---

### Task 24: Hard & soft breaks

**Files:**
- Modify: `Sources/MarkdownAST/BlockParser.swift` (preserve intra-paragraph newlines), `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/BreakTests.swift`

**Interfaces:**
- A newline inside a paragraph becomes `.softBreak`; a line ending with two+ spaces or a backslash becomes `.hardBreak`. The raw paragraph text already joins lines with `\n` (Task 4); the inline parser converts `\n` to `.softBreak`, and trailing `"  \n"`/`"\\\n"` to `.hardBreak`.

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/BreakTests.swift`:

```swift
import Testing
@testable import MarkdownAST

private func inlines(_ s: String) -> [MarkdownInline] {
    guard case .paragraph(let c)? = MarkdownParser.parse(s).blocks.first else { return [] }
    return c
}

@Test func softBreak() {
    #expect(inlines("a\nb") == [.text("a"), .softBreak, .text("b")])
}

@Test func hardBreakTwoSpaces() {
    #expect(inlines("a  \nb") == [.text("a"), .hardBreak, .text("b")])
}

@Test func hardBreakBackslash() {
    #expect(inlines("a\\\nb") == [.text("a"), .hardBreak, .text("b")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in `InlineParser.parse` tokenization, on `\n`: look back at the buffer; if it ends with two+ spaces, trim them and emit `.hardBreak`; if the preceding char was a `\` escape at line end, emit `.hardBreak`; otherwise `.softBreak`. Ensure the backslash-before-newline case is handled before the generic escape rule.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: hard and soft line breaks"
```

---

### Task 25: Footnote references (inline)

**Files:**
- Modify: `Sources/MarkdownAST/InlineParser.swift`
- Test: `Tests/MarkdownASTTests/FootnoteReferenceTests.swift`

**Interfaces:**
- Extends tokenization: `[^id]` becomes `.footnoteReference(id:)` (only when a matching definition exists in `defs`; otherwise literal text).

- [ ] **Step 1: Write failing tests**

`Tests/MarkdownASTTests/FootnoteReferenceTests.swift`:

```swift
import Testing
@testable import MarkdownAST

@Test func footnoteReferenceResolves() {
    let doc = MarkdownParser.parse("Text[^1]\n\n[^1]: note")
    guard case .paragraph(let c)? = doc.blocks.first else { Issue.record("no paragraph"); return }
    #expect(c == [.text("Text"), .footnoteReference(id: "1")])
    #expect(doc.footnotes.first?.id == "1")
}

@Test func unknownFootnoteReferenceIsLiteral() {
    let doc = MarkdownParser.parse("Text[^x]")
    guard case .paragraph(let c)? = doc.blocks.first else { Issue.record("no paragraph"); return }
    #expect(c == [.text("Text[^x]")])
}
```

- [ ] **Step 2: Run, expect FAIL.**

- [ ] **Step 3: Implement** — in tokenization, on `[`, before generic link handling, check for `[^id]`: if `defs.footnotes` contains `id`, emit `.literal(.footnoteReference(id: id))`. (Footnotes are collected in Pass A, so they are available.) Add a `func hasFootnote(_ id: String) -> Bool` to `DefinitionStore`.

- [ ] **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "feat: inline footnote references"
```

---

### Task 26: CommonMark / GFM conformance harness

**Files:**
- Create: `Tests/MarkdownASTTests/Resources/commonmark-spec.json` (downloaded fixture)
- Create: `Tests/MarkdownASTTests/Resources/gfm-spec.json` (or a curated subset)
- Create: `Tests/MarkdownASTTests/ConformanceTests.swift`
- Create: `Tests/MarkdownASTTests/KnownSkips.swift`
- Modify: `Package.swift` (add `resources: [.copy("Resources")]` to the test target)

**Interfaces:**
- Consumes `MarkdownParser.parse`. The fixtures map Markdown → expected HTML; since we produce an AST (not HTML), this harness renders our AST to a minimal canonical HTML string for comparison, OR (recommended) asserts only that parsing does not crash and matches a curated set of AST expectations. Use the AST-based curated approach to avoid building an HTML renderer here.

- [ ] **Step 1: Decide comparison strategy & add a tiny AST→HTML for conformance only**

Add `Tests/MarkdownASTTests/ConformanceHTML.swift` with a minimal, test-only `astToHTML(_:)` covering the in-scope constructs (headings, paragraphs, emphasis/strong/code/strikethrough, links/images, lists, blockquotes, code blocks, hr, tables). This is test code, not shipped.

- [ ] **Step 2: Add the spec fixtures**

```bash
mkdir -p Tests/MarkdownASTTests/Resources
curl -sL https://spec.commonmark.org/0.31.2/spec.json -o Tests/MarkdownASTTests/Resources/commonmark-spec.json
```

For GFM, curate a small JSON of `{markdown, html, section}` cases for tables, task lists, strikethrough, autolinks (hand-authored, ~15 cases) at `Resources/gfm-spec.json`.

- [ ] **Step 3: Write the parameterized conformance test with known-skips**

`Tests/MarkdownASTTests/KnownSkips.swift`:

```swift
// Example numbers (CommonMark example index) we intentionally do not support.
let knownSkippedExamples: Set<Int> = [/* HTML blocks, entity refs, nested links — fill from failures */]
```

`Tests/MarkdownASTTests/ConformanceTests.swift`:

```swift
import Testing
import Foundation
@testable import MarkdownAST

struct SpecCase: Decodable { let markdown: String; let html: String; let example: Int }

func loadSpec(_ name: String) throws -> [SpecCase] {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Resources")!
    return try JSONDecoder().decode([SpecCase].self, from: Data(contentsOf: url))
}

@Test func commonMarkConformance() throws {
    let cases = try loadSpec("commonmark-spec")
    var failures: [Int] = []
    for c in cases where !knownSkippedExamples.contains(c.example) {
        let produced = astToHTML(MarkdownParser.parse(c.markdown))
        if normalizeHTML(produced) != normalizeHTML(c.html) { failures.append(c.example) }
    }
    #expect(failures.isEmpty, "Failing CommonMark examples: \(failures)")
}
```

- [ ] **Step 4: Run, triage, record known-skips**

Run: `swift test --filter ConformanceTests`. Move genuinely out-of-scope failures (HTML blocks, entity refs, nested links) into `knownSkippedExamples` with a comment grouping them by category. Fix any in-scope failures by adding targeted TDD tests in the relevant feature file and correcting the parser. Re-run until green.

- [ ] **Step 5: Commit**

```bash
git add -A && git commit -m "test: CommonMark/GFM conformance harness with documented known-skips"
```

---

### Task 27: Final doc comment & limitations

**Files:**
- Modify: `Sources/MarkdownAST/MarkdownParser.swift`
- Test: (none — doc only; run full suite)

- [ ] **Step 1: Expand the `MarkdownParser` doc comment** to list supported constructs (CommonMark + GFM tables/task-lists/strikethrough/autolinks + footnotes + definition lists) and the documented limitations (HTML blocks/inline, character/entity references, nested links, info strings containing backticks).

- [ ] **Step 2: Run the full suite & lint**

Run: `swift build && swift test`
Expected: all green. If SwiftLint is configured (`swiftlint`), run it and fix violations.

- [ ] **Step 3: Commit**

```bash
git add -A && git commit -m "docs: document MarkdownParser coverage and limitations"
```

---

## Self-Review

**Spec coverage check (each spec section → task):**
- §1 module boundary/API → Task 1, 2
- §2 AST model (all node types) → Task 2
- §3 block parsing (two-pass, containers, leaf dispatch) → Tasks 4–13, 14 (Pass A defs)
- §4 inline parsing (tokenize + delimiter stack) → Tasks 16–25
- §5 extended (tables, task lists, footnotes, definition lists, language hint, autolinks) → Tasks 12, 13, 14, 15, 23, 25; language hint captured in Task 8
- §6 testing (TDD + conformance fixtures) → every task (TDD) + Task 26 (conformance)
- §7 limitations (HTML, entity refs out of scope) → Task 27 doc; enforced by never implementing them
- Success criteria (no deps, no SwiftUI import, build/test green) → Global Constraints + Task 27

**Placeholder scan:** No "TBD/TODO". The one algorithm with an implementation *note* (Task 18 emphasis) provides the structural code plus an explicit fallback algorithm and incremental test cases — acceptable because the test contract is exact.

**Type consistency:** `MarkdownParser.parse`, `BlockParser(defs:).parse`, `InlineParser(defs:).parse`, `DefinitionStore` (links/footnotes/normalize/addLink/link(for:)/addFootnote/hasFootnote), `listMarker`/`parseList`, `splitTableRow`/`delimiterAlignments`, `resolveEmphasis`/`InlineToken`, `parseInlineLinkOrImage`/`matchBracket`/`matchParen` — names used consistently across tasks.

## Notes for the implementer

- `MarkdownTable`/`MarkdownDefinition` cell & term inline content is produced by `InlineParser` once Task 16 lands; Tasks 13/15 initially emit `.text(...)` and Task 16 rewires them to `InlineParser.parse(...)`. After Task 16, re-run Task 13/15 tests — update their expectations only if a cell contains inline markup (the given tests use plain text, so they stay green).
- The emphasis resolver (Task 18) is the riskiest unit. Budget extra iterations; lean on the CommonMark reference `process_emphasis` if the array-rewrite version is hard to stabilize.
