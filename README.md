# swiftui-markdown

A hand-written, **zero-dependency** Markdown parser in pure Swift. It turns
Markdown (CommonMark 0.31 + GFM extensions) into a value-type AST you can render
however you like — no `swift-markdown`, no Foundation in the parser core.

Built test-first (TDD): every feature is driven by a failing test, and the suite
currently has **230 tests**.

## Installation

Swift Package Manager — add the dependency and the `MarkdownAST` product:

```swift
.package(url: "https://github.com/mnshkv/swiftui-markdown.git", branch: "main")
// target dependency: .product(name: "MarkdownAST", package: "swiftui-markdown")
```

Requires Swift 6.2+.

## Usage

```swift
import MarkdownAST

let doc = MarkdownParser.parse("# Hello\n\nWorld with `code`.")
// doc.blocks == [
//   .heading(level: 1, content: [.text("Hello")]),
//   .paragraph(content: [.text("World with "), .code("code"), .text(".")]),
// ]
```

`MarkdownParser.parse` returns a `MarkdownDocument` (`blocks: [MarkdownBlock]`,
`footnotes: [FootnoteDefinition]`). The AST types are plain `enum`/`struct`
values (`Equatable`, `Sendable`, `Hashable`).

## How it works

Parsing is two passes:

1. **Pass A — block structure.** Splits the source into lines (tabs expanded,
   `\n`/`\r\n`/`\r` handled), scans block constructs into a raw tree, and
   collects all link-reference and footnote definitions.
2. **Pass B — inline resolution.** Once every definition is known, each raw leaf
   is parsed into inline nodes. Because inlines resolve after Pass A, references
   defined *after* their use still resolve.

## Status

**Blocks:** ATX & setext headings · paragraphs · fenced & indented code ·
block quotes (nested, lazy continuation) · thematic breaks · GFM tables ·
lists (bullet/ordered, nested, tight/loose, GFM task items `[ ]`/`[x]`) ·
definition lists · link-reference & footnote definitions.

**Inline:** plain text · backslash escapes · code spans · reference links
`[text][label]` · footnote references `[^id]`.

**In progress:** emphasis / strong / strikethrough pairing (the delimiter
tokenizer, char-aware flanking classification, and text coalescing are in
place; the canonical `process_emphasis` pass plus inline links/images/autolinks
land in the next waves).

## Development

```sh
swift build      # build
swift test       # run the test suite
swiftlint        # lint (config in .swiftlint.yml)
```

CI (GitHub Actions) builds, tests, and lints on every push and pull request.

## License

[MIT](LICENSE) — do whatever you want with it.
