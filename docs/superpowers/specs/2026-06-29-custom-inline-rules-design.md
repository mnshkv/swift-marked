# Custom Inline Rules — Design

**Date:** 2026-06-29
**Status:** Approved (design phase)
**Scope:** Extensible, platform-level engine for custom inline syntax (hashtags `#tag`,
mentions `@user`, emoji shortcodes `:smile:`, cashtags `$TSLA`, …) that render as
highlighted/styled text or inline images and are tappable.

## 1. Goal & Motivation

The library renders CommonMark/GFM today, but applications need app-specific inline
tokens that are **not** part of Markdown: hashtags, @-mentions, `:emoji:` shortcodes
that resolve to inline images, etc. These must be:

- **Recognised** from bare text (the author writes `#swift`, not `[#swift](...)`).
- **Highlighted**: custom foreground colour, bold/italic, and an optional rounded
  background "pill".
- **Rendered as inline images** in the emoji case (`:smile:` → an image).
- **Tappable**, dispatching the matched value back to the host app.
- **User-configurable** per `MarkdownView` (a registry of rules passed at the call site),
  not a fixed built-in set.

This is a platform feature, not two hard-coded token types.

## 2. Non-Goals

- No changes to the hand-written CommonMark parser (`Sources/MarkdownAST/`). The 524-test
  conformance baseline (505/652) stays untouched.
- No regex or arbitrary-closure matchers in v1 — matching is **declarative** only.
- No block-level custom syntax (this is inline-only).
- No author-side escaping support for custom rules (see §8 Limitations).
- No global/app-wide singleton registry — rules are per-`MarkdownView`.

## 3. Architecture Decision: where matching runs

Three options were considered:

- **A — Parser-level** (extend `InlineParser.tokenize`, add a `MarkdownInline` case).
  Rejected: forks the precious CommonMark parser, risks the conformance baseline, and
  threads rule config through `MarkdownAST`.
- **B — `InlineMapper`-level transform (CHOSEN).** The rule engine runs exactly where
  `InlineMapper` maps a `.text(s)` AST node into engine runs. The parser is untouched;
  code spans (`.code`, a separate AST case) are naturally excluded; emphasis recursion
  reuses inherited styling; existing `.inlineImage` and `.link` (tap) machinery is reused.
  The only new engine work is the background "pill".
- **C — Post-pass over final `InlineRun`s.** Rejected: loses AST context (harder to
  distinguish code/link), and the rule engine would live in the engine layer, mixing
  concerns.

**Decision: B.** Rules are applied inside the Marked mapping layer; the AST and parser
are not modified.

## 4. Public API (Marked layer)

```swift
public struct InlineRule: Sendable {
    public let id: String              // routing id, e.g. "hashtag", "mention", "emoji"
    public var trigger: Character      // '#', '@', ':'
    public var body: BodyClass         // allowed body characters
    public var closing: Character?     // e.g. ':' for :smile: ; nil → scan until word boundary
    public var minBodyLength: Int      // default 1
    public var requiresLeadingBoundary: Bool  // default true (avoid email@x, c#)
    public var output: Output
    public var isTappable: Bool        // default true

    public enum BodyClass: Sendable {
        case word                      // letters + digits + '_'
        case custom(Set<Character>)
    }
    public enum Output: Sendable {
        case styledText(InlineDecoration)   // colour / bold / italic / pill
        case image(keyPrefix: String)       // :smile: → source = keyPrefix + body
    }
}

public struct InlineDecoration: Sendable {
    public var color: CGColor?         // nil → inherit surrounding colour
    public var isBold: Bool = false
    public var isItalic: Bool = false
    public var background: CGColor?    // pill fill; nil → no background
    public var includeTrigger: Bool = true  // show '#'/'@' in display text; false for :emoji:
}
```

`MarkdownView.init` gains two parameters with defaults (no breaking change):

```swift
rules: [InlineRule] = [],
onCustomTap: ((CustomInlineTap) -> Void)? = nil

public struct CustomInlineTap: Sendable, Equatable {
    public var ruleID: String
    public var value: String   // matched body without trigger, e.g. "swift" for #swift
}
```

`MarkdownRenderer.render(_:style:colorScheme:rules:)` gains `rules: [InlineRule] = []`,
threaded into `InlineMapper`.

## 5. Rule Engine (the core)

A pure function, the single new unit of logic:

```swift
func applyRules(_ s: String,
                rules: [InlineRule],
                base: TextStyle,
                ctx: StyleContext) -> [InlineRun]
```

Algorithm — single O(n) scan, gated on trigger characters:

1. Walk `s` char by char, accumulating plain text in a buffer.
2. At each index whose character equals some rule's `trigger`:
   - Check `requiresLeadingBoundary`: index 0, or the previous char is a non-word char.
   - Scan the body while characters are in `rule.body`.
   - Enforce `minBodyLength`.
   - If `rule.closing != nil`, require that exact closing char immediately after the body
     and consume it.
   - On a match: flush the buffer as `.text(buf, base)`, emit the rule's run, advance the
     cursor past the whole match.
   - On no match: treat the trigger as ordinary text (accumulate).
3. **Rule order in the array is precedence** — the first rule that matches at a position
   wins. Documented behaviour.

Output forms:

- `styledText(decoration)` → `.text(display, decoratedStyle)` where `display` =
  `(includeTrigger ? trigger : "") + body`. `decoratedStyle` is `base` with
  colour/bold/italic/background overlaid. If `isTappable`, wrap in `.link(runs:, payload:)`
  (see §6).
- `image(keyPrefix)` → `.inlineImage(ImageAttachment(source: keyPrefix + body,
  intrinsicSize: ctx.style.inlineImageSize, alt: body))`. Resolved by the host's existing
  `ImageProvider`. If `isTappable`, wrap likewise.

**Recursion & scope:**

- Called from `InlineMapper` for `.text` nodes only, so it runs inside `emphasis` /
  `strong` / `strikethrough` (style inherited) but **never** inside `.code`.
- Inside link content (`.link` AST node), rule application is **suppressed** (a flag passed
  when mapping link children) so the link stays a single tap target.

## 6. Tap round-trip (reuses link infrastructure)

The entire "tappable highlighted span" path already routes through
`LinkPayload { token: String }` → hit-testing → `onLink(payload)`. We reuse it:

- A tappable rule run is `.link(runs: [display], payload: LinkPayload("\u{1}rule\u{1}<id>\u{1}<value>"))`.
  The `\u{1}` (SOH) separator cannot occur in Markdown source.
- `MarkdownRenderer.LinkAction` gains `case custom(ruleID: String, value: String)`.
- `resolveLink(token)`: if the token has the `"\u{1}rule\u{1}"` prefix, parse and return
  `.custom(...)`; otherwise the existing footnote/URL logic is unchanged.
- `MarkdownView.handleLink`: the `switch` gains a `.custom` branch dispatching to
  `onCustomTap`. URL and footnote behaviour is unchanged.
- Pressed-state highlight reuses the existing pressed-link rect mechanism for v1.

## 7. Engine change — background "pill" (the only real engine work)

- `TextStyle` (Model/InlineRun.swift) gains `var background: CGColor?` (default nil);
  `Equatable`/`Sendable` preserved.
- `ParagraphLayout`: while laying out runs (run ranges are already known to the selection
  machinery), collect `[(TextRange, CGColor)]` background boxes and store them on the
  paragraph/document layout.
- `DocumentRenderer.draw`: before drawing glyphs, fill a rounded rectangle behind each
  background run, using the same line-frame → CGRect geometry that selection and
  pressed-link rects use. Corner radius and horizontal padding are constants (candidate to
  live on `MarkdownStyle`).
- Isolated to 2–3 files (`InlineRun`/`Styles`, `ParagraphLayout`, `DocumentRenderer`).

## 8. Edge cases & limitations (documented behaviour)

- **`@` vs GFM email autolink:** `user@host.com` is turned into `.autolink` by the parser,
  so a `mention` rule (which operates on `.text`) never sees it. A bare `@user` stays text
  and matches. This separation is correct and intended.
- **Escaping `\#tag`:** the parser collapses `\#` → `#` text, so escaped triggers are
  indistinguishable from real ones and rules still fire. Known limitation of the
  "don't touch the parser" approach. Revisit only if a concrete need appears.
- **Selection / copy:** styled-text form copies its display text; emoji-image form copies
  its `alt` (the matched body) via the existing image-copy path.
- **Performance:** one O(n) scan, gated on trigger chars; rules whose trigger never appears
  cost essentially nothing.
- **Block `#` headings:** ATX headings are handled at the block level before inline
  parsing, so a heading line never reaches `applyRules`; only inline `#word` matches.

## 9. Testing strategy

- **Rule engine unit tests** (pure `applyRules`): each of the 4 forms (colour text, bold,
  pill, image); leading-boundary enforcement; precedence/order; closing delimiter;
  `minBodyLength`; no-match passthrough; recursion under emphasis; exclusion inside code
  spans and inside link labels.
- **Renderer tests** for the pill: a run with `background != nil` yields background boxes /
  filled rects (pixel-level assertions, mirroring existing `DocumentRenderer` tests).
- **Round-trip tests:** tap token encode → `resolveLink` → `.custom(ruleID, value)` decode.
- **Regression:** all 524 existing tests stay green (parser untouched → conformance
  unchanged).

## 10. Files touched (anticipated)

| File | Change |
|------|--------|
| `Sources/Marked/InlineRule.swift` (new) | Public `InlineRule`, `InlineDecoration`, `CustomInlineTap` |
| `Sources/Marked/InlineRuleEngine.swift` (new) | `applyRules` pure function |
| `Sources/Marked/InlineMapper.swift` | Call `applyRules` for `.text`; suppress flag inside links |
| `Sources/Marked/MarkdownRenderer.swift` | `rules:` param; `LinkAction.custom`; `resolveLink` prefix |
| `Sources/Marked/MarkdownView.swift` | `rules:` + `onCustomTap` params; `.custom` dispatch |
| `Sources/MarkdownTextEngine/Model/InlineRun.swift` | `TextStyle.background` field |
| `Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift` | Collect background boxes |
| `Sources/MarkdownTextEngine/Render/DocumentRenderer.swift` | Draw rounded background fill |
| `Tests/MarkedTests/…` | Rule engine + round-trip tests |
| `Tests/MarkdownTextEngineTests/…` | Pill rendering tests |
