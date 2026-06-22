# Parser Plan — Adversarial Review Report

**Date:** 2026-06-22
**Method:** 8-lens multi-agent review (spec-coverage, algo-block, algo-inline, swift-compile, commonmark-conformance, test-quality, ast-api-design, completeness-critic) → adversarial verification of each finding → synthesis. 95 agents, 74 findings confirmed real (18 critical / 24 major / 32 minor).
**Verdict:** Spec is sound. The PLAN has real defects and is **not ready to implement** as written. Fixes below.

Findings deduplicated into distinct issues. Each maps to the task(s) to change.

---

## CRITICAL (8 distinct) — must fix before coding

### C1. Two-pass parsing is fake; forward references never resolve
**Where:** Task 16 wiring; breaks Task 21 (reference links) & Task 25 (footnote refs) shown tests.
**Problem:** Task 16 calls `InlineParser.parse` at paragraph/heading *flush time*, i.e. eagerly during the single Pass-A walk. A paragraph that precedes its `[label]: url` / `[^id]:` definition is inline-parsed before that definition is collected, so the reference stays literal. The spec's whole reason for two passes (forward references) is defeated. Every shown reference/footnote test uses a forward reference and would FAIL.
**Fix:** Make Pass B genuinely deferred. Add an internal-only inline payload (e.g. `case unparsed(String)` on an internal raw representation, NOT on the public `MarkdownInline`) — store raw leaf text in Pass A; after the full tree is built and `DefinitionStore` is complete, recursively walk the tree replacing raw payloads via `InlineParser(defs:).parse(...)`. Walk paragraph/heading content, table header+row cells, definition terms/details, list items, block quotes, AND `document.footnotes` bodies. Update `MarkdownParser.parse` pipeline to: splitIntoLines → BlockParser (Pass A: raw leaves + defs) → inline walk (Pass B) → document. Renumber so Pass B lands before Tasks 21/25.

### C2. Adjacent `.text` nodes never coalesced
**Where:** Task 18 `emit` / `InlineParser` output; breaks `a * b`, `unmatchedStarIsLiteral`, and most emphasis/escape tests.
**Problem:** Literalized delimiters, escapes, and split text fragments are emitted as separate `.text` nodes; shown tests expect a single merged `.text`. e.g. `a * b` should be `[.text("a * b")]`.
**Fix:** Add a final coalescing pass in `InlineParser.parse` that merges consecutive `.text` nodes into one before returning (recurse into children of emphasis/strong/strikethrough/link). Apply everywhere inline output is produced.

### C3. `resolveEmphasis` is algorithmically wrong (no rule of 3, fragile bookkeeping)
**Where:** Task 18 `EmphasisResolver.resolveEmphasis`.
**Problem:** Nearest-same-char-opener pairing with no rule-of-3 produces wrong nesting for mixed `*` runs (`**a*b*c**`, `***a***`); the `replaceSubrange` index bookkeeping reuses `tokens[i]` after reassignment and resets the cursor, re-scanning consumed regions. Rule of 3 is described in prose but not in code.
**Fix:** Replace the array-rewrite approach with the canonical CommonMark `process_emphasis` (delimiter linked list, `openers_bottom` per (char, canOpen, lengthMod3), rule of 3: forbid pairing when one delimiter can both open and close and `(openerCount + closerCount) % 3 == 0` while neither count % 3 == 0). Rewrite Task 18's implementation block to the canonical algorithm; keep the same shown tests plus the incremental ladder (`*a*`, `**a**`, `***a***`, `*a**b**c*`, `**a*b*c**`).

### C4. Intraword underscore rule missing
**Where:** Task 18 flanking / `canOpen`/`canClose` derivation; breaks `intrawordUnderscoreNotEmphasis` (`a_b_c`).
**Problem:** `_` uses the same open/close rules as `*`, so `a_b_c` parses as emphasis.
**Fix:** Implement CommonMark `_` rules: a `_` can open only if left-flanking AND (not right-flanking OR preceded by punctuation); can close only if right-flanking AND (not left-flanking OR followed by punctuation). `*` keeps the simpler left/right-flanking rules.

### C5. Loose-list detection broken
**Where:** Task 11 `parseList`; breaks `looseListWhenBlankBetweenItems`.
**Problem:** Blank lines between items are swallowed by the inner item-collection loop, so `sawBlank` is never observed at item boundaries and `isTight` stays true; blank lines *inside* an item (multi-paragraph) also fail to mark loose; trailing-blank handling is muddled.
**Fix:** Rework blank-line tracking: a list is loose if any blank line appears between two block-level children (either between items, or between blocks within an item) excluding a trailing blank before the list ends. Track blanks at the boundary between consuming one item and starting the next, and detect blanks separating blocks inside an item. Add tests for multi-paragraph item → loose.

### C6. List dispatch regresses thematic breaks
**Where:** Task 11 dispatch order; breaks Task 6 `thematicBreakVariants` for `- - -`, `* * *`.
**Problem:** The list branch runs before the thematic-break check, so `- - -`/`* * *` parse as bullet lists.
**Fix:** Check `thematicBreak(line)` BEFORE the list branch (CommonMark: a line that is a valid thematic break is a thematic break, not a list item).

### C7. Undefined helper `indexOf`
**Where:** Task 22 autolink tokenization.
**Problem:** `indexOf(chars, ">", from:)` is referenced but never defined.
**Fix:** Define a small helper `func indexOf(_ chars: [Character], _ target: Character, from: Int) -> Int?` (or use a manual scan), and use it consistently.

### C8. Lazy continuation over-broad in blockquotes and lists
**Where:** Task 10 blockquote inner loop (`else if !stripped.isEmpty { inner.append(l) }`); Task 11 `parseList` (`else if listMarker(l) == nil { itemLines.append(l) }`).
**Problem:** Lazy continuation absorbs ANY non-blank line, including following headings, fenced code, thematic breaks, and new list starts that should end/start a new block.
**Fix:** Restrict lazy continuation to *paragraph continuation* only: a line may lazily continue a container only if it is plain paragraph text (not itself a block start — not a heading, fence, thematic break, blockquote marker, or list marker). Add a `isBlockStart(line)` guard.

---

## MAJOR (deduped) — fix before coding

### M1. Soft-break conversion regresses earlier tests
**Where:** Task 24 vs Tasks 4/5/7/9 (which assert embedded `\n` in `.text`).
**Fix:** Earlier tasks should not bake in multi-line `.text` semantics that Task 24 changes. Update Tasks 4/5/9 multi-line expectations to single-line (or pre-declare the softBreak outcome), and at Task 24 add the multi-line → softBreak/hardBreak tests. Call out the rewrite explicitly in Task 24's Interfaces.

### M2. Tabs never expanded
**Where:** Preprocessing (Task 3) and all indentation logic.
**Fix:** Expand tabs to spaces on a 4-column tab stop during/after line splitting, before indentation measurement. Add to Task 3.

### M3. "Up to 3 leading spaces" rule for block starts missing
**Where:** Tasks 5,6,7,8,10 (ATX, thematic break, fenced code, setext, blockquote).
**Fix:** Allow 0–3 leading spaces before these block markers (≥4 is indented code). The helpers already `drop(while: " ")` in places — make the ≤3 bound explicit and consistent.

### M4. Paragraph-interruption rules not enforced
**Where:** Tasks 10/11/13 dispatch; ordered list start≠1 and empty items wrongly interrupt.
**Fix:** A blank-line-free paragraph may only be interrupted by: ATX heading, thematic break, blockquote, fenced code, an *unordered* list start, or an *ordered* list start **with number 1** and a non-empty item. Empty list items and ordered lists starting ≠1 do not interrupt a paragraph. Encode an `canInterruptParagraph` check.

### M5. Definition-list parsing wrong vs model
**Where:** Task 15; model `MarkdownDefinition.details: [[MarkdownBlock]]`.
**Fix:** Collect each `:` line as a SEPARATE detail (multiple definitions per term), and include indented continuation lines (not starting with `:`) into the current detail. Populate `details` as an array. (See open question on cardinality.)

### M6. Fenced code closing-fence rules incomplete
**Where:** Task 8.
**Fix:** Strip leading indentation from content equal to the opening fence's indent; require the closing fence length ≥ opening length; the closing fence line may have ≤3 leading spaces and only trailing whitespace after the fence run; an opening fence may be indented ≤3.

### M7. Link destination/title parsing incomplete
**Where:** Task 20 `splitDestinationAndTitle`/`extractTitle`/`matchParen`.
**Fix:** Handle `<...>` destinations that contain spaces; balanced parens in bare destinations; title delimited by `"`, `'`, or `(...)`; reject when leftover non-title text exists. Add cases.

### M8. GFM table escaped pipe not unescaped; delimiter row too loose
**Where:** Task 13 `splitTableRow`/`delimiterAlignments`.
**Fix:** Unescape `\|` to `|` in cell text after splitting; tighten the delimiter row to require each cell match `:?-+:?` with at least one `-` and the row to consist only of pipes/dashes/colons/space.

### M9. GFM extended autolink trailing-punctuation too simplistic
**Where:** Task 23.
**Fix:** Apply GFM rules: strip trailing `?!.,:*_~` (and unmatched `)`), validate domain has a dot, exclude when followed by certain chars. Add cases for `(https://a.com)` and `https://a.com.`.

### M10. Paragraph continuation lines not left-trimmed
**Where:** Task 4 paragraph accumulation.
**Fix:** Trim leading/trailing whitespace per paragraph line before joining, so indentation doesn't leak into inline text.

### M11. Missing `import Foundation` in `BlockParser.swift`
**Where:** Task 8 (`trimmingCharacters`).
**Fix:** Add `import Foundation` at the top of `BlockParser.swift` when first created (Task 4), not implicitly at Task 8.

### M12. Undefined `normalizeHTML` in conformance test
**Where:** Task 26.
**Fix:** Define `normalizeHTML` (collapse insignificant whitespace between tags) or choose the curated-AST methodology (see open question).

### M13. Footnote multi-paragraph body truncated
**Where:** Task 14 `footnoteDefinition` (only 4-space continuations, stops at first blank line).
**Fix:** Depends on the multi-paragraph decision (open question). If supported: continue collecting indented lines across blank lines until dedent.

---

## MINOR (32) — track, fix opportunistically

Representative items (full list in workflow output `w4if5po73`): strikethrough mixed-length `~` runs underspecified; `setextLevel` vs valid bullet ordering edge; empty-input variants (only whitespace / only blank lines); image-inside-link; nested fence inside list item; table inside blockquote; Unicode flanking/width; recursion depth on deeply nested input; code-block trailing-newline normalization; `isIndentedCode` ternary/precedence clarity; conformance AST→HTML scope underestimate. These do not block implementation but should be folded into the relevant tasks' tests where cheap.

---

## Open questions for the user

1. **Conformance methodology (Task 26):** build a test-only AST→HTML renderer for full CommonMark/GFM `spec.json` HTML comparison (rigorous, real conformance numbers, more work) vs. curated hand-authored AST expectations (lighter, less exhaustive).
2. **Extended depth this iteration:** implement multi-paragraph footnotes, multi-line link-reference definitions, and multi-block definition-list details now — vs. document them as limitations for v1.
3. **Definition-list `details` cardinality:** keep `[[MarkdownBlock]]` (multiple definitions per term) — recommended — or simplify to `[MarkdownBlock]`.

## Decided without user (will apply)

- SwiftLint: optional — run and fix only if a config is present.
- Max-nesting depth: add a cheap recursion-depth guard to avoid stack overflow on pathological input.
- Definition-list cardinality: keep `[[MarkdownBlock]]` unless the user objects.
