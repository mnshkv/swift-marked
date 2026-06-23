## Wave 7 Report — Final gate (Task 7.1)

### README.md changes

- Intro updated: "two layers" → "three layers"; added `Marked` bullet describing the umbrella renderer (`@_exported` re-exports parser + engine, `import Marked` gives everything).
- Test count updated: 475 → **523** (reflects all three modules).
- Installation block: added `Marked` product line; updated platform note to include `Marked`.
- Usage: added **"Render Markdown in SwiftUI (recommended)"** section before the existing text-engine section, showing `import Marked` + `MarkdownView("# Hello\n\nWorld…")` one-liner; noted `openURL` / `onLink` / `ImageProvider` / `MarkdownStyle`.
- Roadmap: marked **Spec 3 (renderer) ✅ done** — all three specs complete.
- Development: test count in comment updated 475 → 523.

### Doc-comment additions

**`MarkdownView`** (`Sources/Marked/MarkdownView.swift`):
Added `## v1 Known Limitations (Spec §7)` section to the type-level doc comment:
- Footnote refs clickable but no scroll-to-anchor.
- Quote-bar / code-box tint / list-marker colour: engine defaults, not `MarkdownStyle`.
- System fonts only (no custom families).
- `softBreak` renders as a space.

**`MarkdownRenderer.render(_:style:colorScheme:)`** (`Sources/Marked/MarkdownRenderer.swift`):
Added `## v1 Known Limitations (Spec §7)` section to the String-overload doc comment with the same four items.

### Gate results

```
swift build
  → Build complete! (0.58s)

swift test
  → Test run with 523 tests in 82 suites passed after 0.077 seconds.

xcodebuild build -scheme Marked -destination 'generic/platform=iOS'
  → ** BUILD SUCCEEDED **

swiftlint lint --quiet | grep -c ': error:'
  → 0
```

All gates green. Zero lint errors. 523/523 tests pass. iOS build succeeded.

---

## Wave 7 Addendum — Final Review Fixes (post-gate)

### Fix 1 (Important): `headingSizes` out-of-bounds crash

**File:** `Sources/Marked/StyleContext.swift`

**Change:** `heading(_ level:)` now uses a total array access:
```swift
let i = clamped - 1
let size = (i < style.headingSizes.count) ? style.headingSizes[i] : (style.headingSizes.last ?? style.baseFontSize)
```
A consumer supplying `headingSizes: [20]` or `headingSizes: []` no longer traps.

**Regression tests added** in `Tests/MarkedTests/StyleContextTests.swift`:
- `headingSizesShortFallback`: `headingSizes: [20]` → `heading(1)` returns 20, `heading(3)` and `heading(6)` fall back to 20 (last element). Old code would trap on `headingSizes[2]` and `headingSizes[5]`.
- `headingSizesEmptyFallback`: `headingSizes: []` → `heading(1)` returns `baseFontSize` (17). Old code would trap on `headingSizes[-1]` (after clamping, `headingSizes[0]` on empty array).

Both tests fail on the old indexing (confirmed: the old `style.headingSizes[clamped - 1]` with a 1-element or 0-element array causes a Swift runtime trap / index out of range).

### Fix 2 (DRY): Consolidate duplicate `indent` helpers

**Files:** `Sources/Marked/BlockMapper.swift`, `Sources/Marked/MarkdownRenderer.swift`

**Change:** `BlockMapper.indent(_:by:)` promoted from `private static` to `static` (internal). The free function `indentBlock(_:by:)` in `MarkdownRenderer.swift` deleted; the call site updated to `BlockMapper.indent(block, by: ...)`. Identical behavior: adds `leadingIndent` to a `.paragraph`'s ParagraphStyle, other block kinds pass through unchanged.

**Covering tests:** definition-list tests in `SpecialFeaturesTests` and footnotes-section tests in `RendererTests` all pass (524 green).

### Fix 3 (Dead code): Remove unused `StyleContext` members

**File:** `Sources/Marked/StyleContext.swift`

**Deleted:**
- `var inlineCode: TextStyle` — InlineMapper builds inline-code style inline from `base` (sets `isMonospace`, `color`, `fontSize` directly).
- `func indentedParagraph(_:) -> ParagraphStyle` — indentation uses `BlockMapper.indent` helper, not this method.

**Test update:** `StyleContextTests.swift` line `#expect(light.inlineCode.isMonospace)` removed (would fail to compile after deletion).

### Fix 4 (Tests): Strengthen brittle/weak tests

**`InlineMapperTests.swift`** — inline-image test: replaced `CGSize(width: 18, height: 18)` hardcode with `ctx.style.inlineImageSize`. Test now tracks style configuration rather than a magic literal.

**`BlockMapperTests.swift`** — `thematicBreak` test: added `#expect(rs.color == ctx.palette.rule)` after the `guard case .thematicBreak(let rs)` pattern match.

**`SpecialFeaturesTests.swift`** — `mixedParagraphStaysInline` test: added `#expect(p.runs.contains { if case .inlineImage = $0 { true } else { false } })` to verify the inline image run is present (not silently dropped).

**`LinkResolveTests.swift`** — deleted the `relativeToken` test: the `if let _ = URL(string: token)` branch is always taken (URL accepts `"path/to/page"`), so the test could never exercise the `.ignore` branch — it was a vacuous tautology.

### Gate results

```
swift build
  → Build complete! (0.74s)

swift test
  → Test run with 524 tests in 82 suites passed after 0.080 seconds.
  (+2 new headingSizes regression tests, -1 deleted vacuous relativeToken test = net +1)

swiftlint lint --quiet Sources/Marked Tests/MarkedTests | grep -c ': error:'
  → 0
```
