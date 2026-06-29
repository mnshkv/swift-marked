# Custom Inline Rules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a per-`MarkdownView`, declarative engine for custom inline tokens (hashtags, mentions, emoji shortcodes) that render as styled/pilled text or inline images and are tappable.

**Architecture:** Rules are applied inside the Marked mapping layer where `InlineMapper` turns a `.text` AST node into engine runs (approach B from the spec). The CommonMark parser and AST are untouched. Tappability reuses the existing `LinkPayload`/`onLink` hit-test machinery via an opaque routing token; emoji reuse the existing `.inlineImage` run; only the rounded "pill" background is new engine work.

**Tech Stack:** Swift 6.2, SwiftUI, CoreText/CoreGraphics, Swift Testing (`import Testing`), no external dependencies.

## Global Constraints

- Platform floor: `.iOS("17.0")`, `.macOS("14.0")` (Package.swift). `MarkdownView` is `@available(iOS 17, macOS 14, *)`.
- swift-tools-version 6.2; Swift 6 concurrency — every public type must be `Sendable`. `CGColor` is treated as `Sendable`/`Equatable` (as existing `TextStyle`/`MarkdownStyle.Palette` already do).
- No third-party dependencies. The hand-written parser in `Sources/MarkdownAST/` MUST NOT be modified — the 524-test suite and CommonMark conformance baseline (≥505/652) stay green.
- Tests use Swift Testing (`@Suite`, `@Test`, `#expect`, `Issue.record`) and `@testable import`.
- `DocumentRenderer.swift` / `ParagraphLayout.swift` import ONLY CoreText + CoreGraphics — never SwiftUI/UIKit/AppKit.
- Backward compatibility: all new parameters are added with defaults; no existing call site or test may break.

---

### Task 1: Public rule types

**Files:**
- Create: `Sources/Marked/InlineRule.swift`
- Test: `Tests/MarkedTests/InlineRuleTypeTests.swift`

**Interfaces:**
- Produces: `InlineRule`, `InlineRule.BodyClass` (`.word` / `.custom(Set<Character>)` with `func contains(_:) -> Bool`), `InlineRule.Output` (`.styledText(InlineDecoration)` / `.image(keyPrefix: String)`), `InlineDecoration`, `CustomInlineTap`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/InlineRuleTypeTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("InlineRule public types")
struct InlineRuleTypeTests {
    @Test("BodyClass.word matches letters, digits, underscore; not punctuation/space")
    func wordClass() {
        let w = InlineRule.BodyClass.word
        #expect(w.contains("a"))
        #expect(w.contains("7"))
        #expect(w.contains("_"))
        #expect(!w.contains("-"))
        #expect(!w.contains(" "))
    }

    @Test("BodyClass.custom matches only its set")
    func customClass() {
        let c = InlineRule.BodyClass.custom(["A", "B"])
        #expect(c.contains("A"))
        #expect(!c.contains("C"))
    }

    @Test("InlineRule defaults: word body, tappable, leading boundary, minBodyLength 1, no closing")
    func ruleDefaults() {
        let r = InlineRule(id: "hashtag", trigger: "#", output: .styledText(InlineDecoration()))
        #expect(r.id == "hashtag")
        #expect(r.trigger == "#")
        #expect(r.isTappable)
        #expect(r.requiresLeadingBoundary)
        #expect(r.minBodyLength == 1)
        #expect(r.closing == nil)
    }

    @Test("InlineDecoration defaults: no colour/background, includeTrigger true")
    func decorationDefaults() {
        let d = InlineDecoration()
        #expect(d.color == nil)
        #expect(!d.isBold)
        #expect(!d.isItalic)
        #expect(d.background == nil)
        #expect(d.includeTrigger)
    }

    @Test("CustomInlineTap is Equatable by ruleID and value")
    func tapEquatable() {
        #expect(CustomInlineTap(ruleID: "a", value: "b") == CustomInlineTap(ruleID: "a", value: "b"))
        #expect(CustomInlineTap(ruleID: "a", value: "b") != CustomInlineTap(ruleID: "a", value: "c"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InlineRuleTypeTests`
Expected: FAIL — `cannot find 'InlineRule' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Marked/InlineRule.swift
import CoreGraphics

/// A declarative rule for recognising a custom inline token (hashtag, mention,
/// emoji shortcode, …) inside plain text and rendering it specially.
public struct InlineRule: Sendable {
    /// Routing identifier returned to the host on tap, e.g. "hashtag".
    public let id: String
    /// The character that opens the token, e.g. "#", "@", ":".
    public var trigger: Character
    /// The set of characters allowed in the token body.
    public var body: BodyClass
    /// Optional closing delimiter (e.g. ":" for `:smile:`). When nil, the body
    /// is scanned until the first character not in `body`.
    public var closing: Character?
    /// Minimum number of body characters required for a match (default 1).
    public var minBodyLength: Int
    /// When true (default), the trigger must start the text or be preceded by a
    /// non-word character (so `email@host` does not match an `@` rule).
    public var requiresLeadingBoundary: Bool
    /// How a matched token is rendered.
    public var output: Output
    /// When true (default), the rendered span is tappable and dispatches a
    /// `CustomInlineTap` to the host.
    public var isTappable: Bool

    public init(
        id: String,
        trigger: Character,
        body: BodyClass = .word,
        closing: Character? = nil,
        minBodyLength: Int = 1,
        requiresLeadingBoundary: Bool = true,
        output: Output,
        isTappable: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.body = body
        self.closing = closing
        self.minBodyLength = minBodyLength
        self.requiresLeadingBoundary = requiresLeadingBoundary
        self.output = output
        self.isTappable = isTappable
    }

    /// The characters permitted in a token body.
    public enum BodyClass: Sendable {
        /// Letters, digits and underscore.
        case word
        /// An explicit set of allowed characters.
        case custom(Set<Character>)

        func contains(_ c: Character) -> Bool {
            switch self {
            case .word: return c.isLetter || c.isNumber || c == "_"
            case .custom(let set): return set.contains(c)
            }
        }
    }

    /// How a matched token renders.
    public enum Output: Sendable {
        /// Render as styled text (colour, bold, italic, optional pill background).
        case styledText(InlineDecoration)
        /// Render as an inline image whose source key is `keyPrefix + body`,
        /// resolved by the host's `ImageProvider`.
        case image(keyPrefix: String)
    }
}

/// Visual decoration applied to a `.styledText` rule match.
public struct InlineDecoration: Sendable {
    /// Foreground colour; nil inherits the surrounding text colour.
    public var color: CGColor?
    public var isBold: Bool
    public var isItalic: Bool
    /// Rounded background "pill" colour; nil draws no background.
    public var background: CGColor?
    /// Whether the trigger character is part of the displayed text
    /// (true for `#tag`/`@user`, false for `:emoji:` shortcodes).
    public var includeTrigger: Bool

    public init(
        color: CGColor? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        background: CGColor? = nil,
        includeTrigger: Bool = true
    ) {
        self.color = color
        self.isBold = isBold
        self.isItalic = isItalic
        self.background = background
        self.includeTrigger = includeTrigger
    }
}

/// Delivered to `MarkdownView`'s `onCustomTap` when a custom rule span is tapped.
public struct CustomInlineTap: Sendable, Equatable {
    /// The `InlineRule.id` of the rule that produced the span.
    public var ruleID: String
    /// The matched body text, without trigger/closing delimiters (e.g. "swift").
    public var value: String

    public init(ruleID: String, value: String) {
        self.ruleID = ruleID
        self.value = value
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InlineRuleTypeTests`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marked/InlineRule.swift Tests/MarkedTests/InlineRuleTypeTests.swift
git commit -m "feat(marked): public InlineRule/InlineDecoration/CustomInlineTap types"
```

---

### Task 2: Tap routing token + `LinkAction.custom`

**Files:**
- Create: `Sources/Marked/InlineRuleToken.swift`
- Modify: `Sources/Marked/MarkdownRenderer.swift` (`LinkAction` enum lines 90-94; `resolveLink` lines 103-112)
- Test: `Tests/MarkedTests/InlineRuleTokenTests.swift`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `InlineRuleToken.encode(ruleID:value:) -> String`, `InlineRuleToken.decode(_:) -> (ruleID: String, value: String)?`, `LinkAction.custom(ruleID: String, value: String)`. Task 5 calls `encode`; Task 8 reads `.custom`.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/InlineRuleTokenTests.swift
import Testing
import Foundation
@testable import Marked

@Suite("Custom-rule tap round-trip")
struct InlineRuleTokenTests {
    @Test("encode then decode recovers ruleID and value")
    func roundTrip() {
        let t = InlineRuleToken.encode(ruleID: "hashtag", value: "swift")
        let d = InlineRuleToken.decode(t)
        #expect(d?.ruleID == "hashtag")
        #expect(d?.value == "swift")
    }

    @Test("decode returns nil for non-rule tokens")
    func decodeNonRule() {
        #expect(InlineRuleToken.decode("https://swift.org")?.ruleID == nil)
        #expect(InlineRuleToken.decode("footnote:1")?.ruleID == nil)
    }

    @Test("resolveLink maps a rule token to .custom")
    func resolveCustom() {
        let token = InlineRuleToken.encode(ruleID: "mention", value: "alice")
        #expect(MarkdownRenderer.resolveLink(token) == .custom(ruleID: "mention", value: "alice"))
    }

    @Test("resolveLink still maps a URL to .url")
    func resolveURLStillWorks() {
        #expect(MarkdownRenderer.resolveLink("https://swift.org") == .url(URL(string: "https://swift.org")!))
    }

    @Test("resolveLink still maps a footnote token to .footnote")
    func resolveFootnoteStillWorks() {
        #expect(MarkdownRenderer.resolveLink("footnote:x") == .footnote("x"))
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InlineRuleTokenTests`
Expected: FAIL — `cannot find 'InlineRuleToken' in scope`.

- [ ] **Step 3: Write minimal implementation**

Create `Sources/Marked/InlineRuleToken.swift`:

```swift
/// Encodes/decodes the opaque `LinkPayload.token` used to route custom-rule taps
/// through the existing link machinery. Uses U+0001 (SOH) separators, which
/// cannot occur in Markdown source text.
enum InlineRuleToken {
    static let prefix = "\u{1}rule\u{1}"

    /// Builds the payload token for a tappable custom-rule span.
    static func encode(ruleID: String, value: String) -> String {
        "\(prefix)\(ruleID)\u{1}\(value)"
    }

    /// Decodes a token produced by `encode`. Returns nil if `token` is not a
    /// custom-rule token.
    static func decode(_ token: String) -> (ruleID: String, value: String)? {
        guard token.hasPrefix(prefix) else { return nil }
        let rest = token.dropFirst(prefix.count)
        guard let sep = rest.firstIndex(of: "\u{1}") else { return nil }
        let ruleID = String(rest[rest.startIndex..<sep])
        let value = String(rest[rest.index(after: sep)...])
        return (ruleID, value)
    }
}
```

In `Sources/Marked/MarkdownRenderer.swift`, replace the `LinkAction` enum (lines 90-94):

```swift
/// The action to take when a link token is activated.
public enum LinkAction: Equatable {
    case url(URL)
    case footnote(String)
    case custom(ruleID: String, value: String)
    case ignore
}
```

And replace the body of `resolveLink` (lines 103-112) so the rule prefix is checked first:

```swift
    static func resolveLink(_ token: String) -> LinkAction {
        if let (ruleID, value) = InlineRuleToken.decode(token) {
            return .custom(ruleID: ruleID, value: value)
        }
        let footnotePrefix = "footnote:"
        if token.hasPrefix(footnotePrefix) {
            return .footnote(String(token.dropFirst(footnotePrefix.count)))
        }
        guard !token.isEmpty, let url = URL(string: token) else {
            return .ignore
        }
        return .url(url)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InlineRuleTokenTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marked/InlineRuleToken.swift Sources/Marked/MarkdownRenderer.swift Tests/MarkedTests/InlineRuleTokenTests.swift
git commit -m "feat(marked): custom-rule tap token + LinkAction.custom resolution"
```

---

### Task 3: `TextStyle.background` field

**Files:**
- Modify: `Sources/MarkdownTextEngine/Model/InlineRun.swift` (`TextStyle` struct, lines 3-15)
- Test: `Tests/MarkdownTextEngineTests/TextStyleBackgroundTests.swift`

**Interfaces:**
- Produces: `TextStyle.background: CGColor?` (defaulted to nil in the memberwise init). Tasks 4 and 5 set it.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkdownTextEngineTests/TextStyleBackgroundTests.swift
import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("TextStyle.background")
struct TextStyleBackgroundTests {
    @Test("background defaults to nil")
    func defaultNil() {
        let a = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
        #expect(a.background == nil)
    }

    @Test("two styles differing only in background are not equal")
    func backgroundAffectsEquality() {
        let base = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1))
        let withBg = TextStyle(fontSize: 17, color: CGColor(gray: 0, alpha: 1),
                               background: CGColor(red: 0, green: 1, blue: 0, alpha: 1))
        #expect(base != withBg)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TextStyleBackgroundTests`
Expected: FAIL — `extra argument 'background' in call`.

- [ ] **Step 3: Write minimal implementation**

Replace the `TextStyle` struct in `Sources/MarkdownTextEngine/Model/InlineRun.swift` (lines 3-15):

```swift
public struct TextStyle: Equatable, Sendable {
    public var fontSize: CGFloat
    public var isBold: Bool
    public var isItalic: Bool
    public var isStrikethrough: Bool
    public var isMonospace: Bool
    public var color: CGColor
    public var background: CGColor?
    public init(fontSize: CGFloat, isBold: Bool = false, isItalic: Bool = false,
                isStrikethrough: Bool = false, isMonospace: Bool = false,
                color: CGColor, background: CGColor? = nil) {
        self.fontSize = fontSize; self.isBold = isBold; self.isItalic = isItalic
        self.isStrikethrough = isStrikethrough; self.isMonospace = isMonospace
        self.color = color; self.background = background
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TextStyleBackgroundTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownTextEngine/Model/InlineRun.swift Tests/MarkdownTextEngineTests/TextStyleBackgroundTests.swift
git commit -m "feat(text-engine): optional TextStyle.background for pill rendering"
```

---

### Task 4: Render the pill background

**Files:**
- Modify: `Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift` (add attribute constant near line 26; `.text` case in `appendRuns`, lines 41-52)
- Modify: `Sources/MarkdownTextEngine/Render/DocumentRenderer.swift` (`drawTextLines`, lines 232-247; add helper + constants)
- Test: `Tests/MarkdownTextEngineTests/PillRenderTests.swift`

**Interfaces:**
- Consumes: `TextStyle.background` (Task 3).
- Produces: a per-run pill drawn behind glyphs whenever `background != nil`. Internal only.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkdownTextEngineTests/PillRenderTests.swift
import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Custom-rule pill background rendering")
struct PillRenderTests {
    @Test("a run with a green background paints green pixels behind the text")
    func pillPaintsBackground() throws {
        let w = 400, h = 60
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let style = TextStyle(fontSize: 20, color: CGColor(gray: 0, alpha: 1), background: green)
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Tag", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [])

        // The pill extends ~3pt left of the glyphs (pillPaddingH), so the top-left
        // zone should contain saturated-green pixels.
        var foundGreen = false
        outer: for y in 0..<20 {
            for x in 0..<60 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.g > 200 && px.r < 120 && px.b < 120 { foundGreen = true; break outer }
            }
        }
        #expect(foundGreen, "Expected green pill pixels behind the tagged run")
    }

    @Test("a run with no background leaves the corner white (no regression)")
    func noBackgroundNoFill() throws {
        let w = 400, h = 60
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let style = TextStyle(fontSize: 20, color: CGColor(gray: 0, alpha: 1))
        let doc = TextDocument(blocks: [
            .paragraph(Paragraph(runs: [.text("Tag", style)], style: .body))
        ])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [])

        let corner = pixel(at: 390, y: 55, width: w, buffer: buffer)
        #expect(corner.r == 255 && corner.g == 255 && corner.b == 255)
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter PillRenderTests`
Expected: FAIL — `pillPaintsBackground` finds no green (background not drawn yet).

- [ ] **Step 3a: Attach the background attribute during layout**

In `Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift`, add this constant just below the imports (after line 2):

```swift
/// Custom CFAttributedString key carrying a per-run pill background colour.
/// Read back at draw time by `DocumentRenderer` to fill a rounded background.
let markedBackgroundAttributeName = "MarkedBackgroundColor" as CFString
```

Then replace the `.text` case in `appendRuns` (lines 41-52) so the attribute is added when present (note `let attrs` becomes `var attrs`):

```swift
        case .text(let string, let style):
            lastStyle = style
            let font = ctFont(for: style)
            var attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: style.color
            ]
            if let bg = style.background {
                attrs[markedBackgroundAttributeName] = bg
            }
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), string as CFString)
            let newLen = CFAttributedStringGetLength(attrStr)
            CFAttributedStringSetAttributes(attrStr, CFRangeMake(len, newLen - len),
                                            attrs as CFDictionary, true)
```

- [ ] **Step 3b: Draw the pill in DocumentRenderer**

In `Sources/MarkdownTextEngine/Render/DocumentRenderer.swift`, add these constants just above `drawTextLines` (before line 231):

```swift
    /// Corner radius of the custom-rule pill background, in points.
    private static let pillCornerRadius: CGFloat = 4
    /// Horizontal padding added on each side of a pill background, in points.
    private static let pillPaddingH: CGFloat = 3
```

Replace `drawTextLines` (lines 232-247) with a version that fills run backgrounds before drawing glyphs, plus a new helper:

```swift
    /// Draws CoreText lines from a `.text` block.
    private static func drawTextLines(_ lines: [LineFrame], in ctx: CGContext, visible: CGRect) {
        for line in lines {
            let lineRect = CGRect(origin: line.origin, size: line.size)
            guard lineRect.intersects(visible) else { continue }

            // Pills are drawn first so glyphs paint on top of them.
            drawRunBackgrounds(for: line, in: ctx)

            let baseline = CGPoint(x: line.origin.x, y: line.origin.y + line.ascent)
            ctx.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
            ctx.textPosition = baseline
            CTLineDraw(line.ctLine, ctx)
        }
    }

    /// Fills a rounded "pill" behind any CTRun carrying the
    /// `markedBackgroundAttributeName` attribute. Operates in the caller's
    /// already-y-flipped document space (same convention as selection rects).
    private static func drawRunBackgrounds(for line: LineFrame, in ctx: CGContext) {
        let runs = CTLineGetGlyphRuns(line.ctLine) as! [CTRun]
        for run in runs {
            let attrs = CTRunGetAttributes(run)
            let keyPtr = Unmanaged.passUnretained(markedBackgroundAttributeName).toOpaque()
            guard CFDictionaryContainsKey(attrs, keyPtr) else { continue }
            guard let valuePtr = CFDictionaryGetValue(attrs, keyPtr) else { continue }
            let color = Unmanaged<CGColor>.fromOpaque(valuePtr).takeUnretainedValue()

            let range = CTRunGetStringRange(run)
            let startX = CTLineGetOffsetForStringIndex(line.ctLine, range.location, nil)
            let endX = CTLineGetOffsetForStringIndex(line.ctLine, range.location + range.length, nil)

            let rect = CGRect(
                x: line.origin.x + min(startX, endX) - pillPaddingH,
                y: line.origin.y,
                width: abs(endX - startX) + 2 * pillPaddingH,
                height: line.size.height
            )
            let path = CGPath(roundedRect: rect, cornerWidth: pillCornerRadius,
                              cornerHeight: pillCornerRadius, transform: nil)
            ctx.addPath(path)
            ctx.setFillColor(color)
            ctx.fillPath()
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter PillRenderTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/MarkdownTextEngine/Layout/ParagraphLayout.swift Sources/MarkdownTextEngine/Render/DocumentRenderer.swift Tests/MarkdownTextEngineTests/PillRenderTests.swift
git commit -m "feat(text-engine): draw rounded pill background for runs with TextStyle.background"
```

---

### Task 5: `InlineRuleEngine.apply` — the matcher

**Files:**
- Create: `Sources/Marked/InlineRuleEngine.swift`
- Test: `Tests/MarkedTests/InlineRuleEngineTests.swift`

**Interfaces:**
- Consumes: `InlineRule`/`InlineDecoration` (Task 1), `InlineRuleToken.encode` (Task 2), `TextStyle.background` (Task 3), `StyleContext` (existing — `ctx.style.inlineImageSize`, `ctx.body`).
- Produces: `InlineRuleEngine.apply(_ s: String, rules: [InlineRule], base: TextStyle, ctx: StyleContext) -> [InlineRun]`. Task 6 calls it.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/InlineRuleEngineTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("InlineRuleEngine")
struct InlineRuleEngineTests {
    let ctx = StyleContext(.default, .light)
    var base: TextStyle { ctx.body }

    let hashtag = InlineRule(id: "hashtag", trigger: "#",
        output: .styledText(InlineDecoration(color: CGColor(red: 0, green: 0, blue: 1, alpha: 1))))
    let mention = InlineRule(id: "mention", trigger: "@",
        output: .styledText(InlineDecoration(isBold: true)))
    let emoji = InlineRule(id: "emoji", trigger: ":", closing: ":",
        output: .image(keyPrefix: "emoji:"), isTappable: false)

    func apply(_ s: String, _ rules: [InlineRule]) -> [InlineRun] {
        InlineRuleEngine.apply(s, rules: rules, base: base, ctx: ctx)
    }

    @Test("no rules → single text run unchanged")
    func passthrough() {
        let runs = InlineRuleEngine.apply("plain #x", rules: [], base: base, ctx: ctx)
        #expect(runs == [.text("plain #x", base)])
    }

    @Test("hashtag becomes a tappable blue text run with the # kept")
    func hashtagMatch() {
        let runs = apply("hi #swift!", [hashtag])
        #expect(runs.count == 3)
        guard case .text(let pre, _) = runs[0] else { Issue.record("pre"); return }
        #expect(pre == "hi ")
        guard case .link(let inner, let payload) = runs[1] else { Issue.record("link"); return }
        guard case .text(let disp, let st) = inner.first else { Issue.record("inner"); return }
        #expect(disp == "#swift")
        #expect(st.color == CGColor(red: 0, green: 0, blue: 1, alpha: 1))
        #expect(InlineRuleToken.decode(payload.token)?.value == "swift")
        guard case .text(let post, _) = runs[2] else { Issue.record("post"); return }
        #expect(post == "!")
    }

    @Test("leading boundary: email@host does not match @mention")
    func leadingBoundary() {
        #expect(apply("email@host", [mention]) == [.text("email@host", base)])
    }

    @Test("@ at start of text matches and is bold")
    func mentionAtStart() {
        let runs = apply("@alice", [mention])
        guard case .link(let inner, _) = runs.first else { Issue.record("link"); return }
        guard case .text(let disp, let st) = inner.first else { Issue.record("inner"); return }
        #expect(disp == "@alice")
        #expect(st.isBold)
    }

    @Test("emoji shortcode becomes an inline image; trigger and delimiters dropped")
    func emojiMatch() {
        let runs = apply("hi :smile: there", [emoji])
        #expect(runs.count == 3)
        guard case .inlineImage(let att) = runs[1] else { Issue.record("image"); return }
        #expect(att.source == "emoji:smile")
        #expect(att.alt == "smile")
    }

    @Test("closing delimiter required: ':smile' without closing colon does not match")
    func emojiNeedsClosing() {
        #expect(apply(":smile", [emoji]) == [.text(":smile", base)])
    }

    @Test("empty body: a bare '#' with a following space does not match")
    func emptyBody() {
        #expect(apply("a # b", [hashtag]) == [.text("a # b", base)])
    }

    @Test("rule order is precedence: first matching rule wins")
    func precedence() {
        let a = InlineRule(id: "first", trigger: "#",
            output: .styledText(InlineDecoration(isBold: true)))
        let b = InlineRule(id: "second", trigger: "#",
            output: .styledText(InlineDecoration(isItalic: true)))
        let runs = apply("#x", [a, b])
        guard case .link(_, let payload) = runs.first else { Issue.record("link"); return }
        #expect(InlineRuleToken.decode(payload.token)?.ruleID == "first")
    }

    @Test("background decoration flows into the run's TextStyle.background")
    func pillStyle() {
        let green = CGColor(red: 0, green: 1, blue: 0, alpha: 1)
        let r = InlineRule(id: "tag", trigger: "#",
            output: .styledText(InlineDecoration(background: green)), isTappable: false)
        let runs = apply("#x", [r])
        guard case .text(_, let st) = runs.first else { Issue.record("text"); return }
        #expect(st.background == green)
    }

    @Test("includeTrigger false drops the trigger from display text")
    func dropTrigger() {
        let r = InlineRule(id: "bare", trigger: "#",
            output: .styledText(InlineDecoration(includeTrigger: false)), isTappable: false)
        let runs = apply("#x", [r])
        guard case .text(let disp, _) = runs.first else { Issue.record("text"); return }
        #expect(disp == "x")
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InlineRuleEngineTests`
Expected: FAIL — `cannot find 'InlineRuleEngine' in scope`.

- [ ] **Step 3: Write minimal implementation**

```swift
// Sources/Marked/InlineRuleEngine.swift
import CoreGraphics

/// Applies a set of `InlineRule`s to a plain-text string, producing a mix of
/// plain-text, styled-text, inline-image and tappable runs. Pure and synchronous.
enum InlineRuleEngine {

    /// Splits `s` into runs, replacing rule matches with their styled/image output.
    /// `base` is the surrounding text style so matches inherit emphasis, colour, etc.
    static func apply(
        _ s: String,
        rules: [InlineRule],
        base: TextStyle,
        ctx: StyleContext
    ) -> [InlineRun] {
        guard !rules.isEmpty, !s.isEmpty else { return [.text(s, base)] }

        let chars = Array(s)
        var runs: [InlineRun] = []
        var buf = ""
        var i = 0

        func flush() {
            if !buf.isEmpty { runs.append(.text(buf, base)); buf = "" }
        }

        while i < chars.count {
            let c = chars[i]
            var matched = false
            // First rule (array order = precedence) that matches at i wins.
            for rule in rules where rule.trigger == c {
                if rule.requiresLeadingBoundary, i > 0, isWordChar(chars[i - 1]) {
                    continue
                }
                guard let m = match(rule, chars, from: i) else { continue }
                flush()
                runs.append(makeRun(rule, value: m.body, base: base, ctx: ctx))
                i = m.end
                matched = true
                break
            }
            if matched { continue }
            buf.append(c)
            i += 1
        }
        flush()
        return runs
    }

    // MARK: - Matching

    private static func isWordChar(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c == "_"
    }

    /// Attempts to match `rule` at `start` (the trigger char). Returns the body
    /// text and the index just past the whole match.
    private static func match(
        _ rule: InlineRule, _ chars: [Character], from start: Int
    ) -> (body: String, end: Int)? {
        var j = start + 1
        var body = ""
        while j < chars.count, rule.body.contains(chars[j]) {
            body.append(chars[j]); j += 1
        }
        guard body.count >= rule.minBodyLength else { return nil }
        if let close = rule.closing {
            guard j < chars.count, chars[j] == close else { return nil }
            j += 1  // consume closing delimiter
        }
        return (body, j)
    }

    // MARK: - Run construction

    private static func makeRun(
        _ rule: InlineRule, value: String, base: TextStyle, ctx: StyleContext
    ) -> InlineRun {
        let inner: InlineRun
        switch rule.output {
        case .styledText(let d):
            var st = base
            if let color = d.color { st.color = color }
            if d.isBold { st.isBold = true }
            if d.isItalic { st.isItalic = true }
            st.background = d.background
            let display = (d.includeTrigger ? String(rule.trigger) : "") + value
            inner = .text(display, st)
        case .image(let keyPrefix):
            inner = .inlineImage(ImageAttachment(
                source: keyPrefix + value,
                intrinsicSize: ctx.style.inlineImageSize,
                alt: value
            ))
        }
        guard rule.isTappable else { return inner }
        return .link(runs: [inner],
                     payload: LinkPayload(InlineRuleToken.encode(ruleID: rule.id, value: value)))
    }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InlineRuleEngineTests`
Expected: PASS (10 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marked/InlineRuleEngine.swift Tests/MarkedTests/InlineRuleEngineTests.swift
git commit -m "feat(marked): InlineRuleEngine declarative matcher for custom inline tokens"
```

---

### Task 6: Wire rules into `StyleContext` + `InlineMapper`

**Files:**
- Modify: `Sources/Marked/StyleContext.swift` (struct + init, lines 5-13)
- Modify: `Sources/Marked/InlineMapper.swift` (`map`, lines 4-34)
- Test: `Tests/MarkedTests/InlineMapperRulesTests.swift`

**Interfaces:**
- Consumes: `InlineRuleEngine.apply` (Task 5), `InlineRule` (Task 1).
- Produces: `StyleContext(_:_:rules:)` with `ctx.rules: [InlineRule]`; `InlineMapper.map(_:base:ctx:footnotes:suppressRules:)` applies rules to `.text` nodes (off inside link labels). Task 7 supplies the rules.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/InlineMapperRulesTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("InlineMapper with custom rules")
struct InlineMapperRulesTests {
    let hashtag = InlineRule(id: "hashtag", trigger: "#",
        output: .styledText(InlineDecoration(isBold: true)))
    var ctx: StyleContext { StyleContext(.default, .light, rules: [hashtag]) }

    @Test("hashtag in plain text is mapped to a tappable link run")
    func textRule() {
        let runs = InlineMapper.map([.text("a #x")], base: ctx.body, ctx: ctx, footnotes: [:])
        #expect(runs.count == 2)
        guard case .link = runs[1] else { Issue.record("expected link run"); return }
    }

    @Test("hashtag inside emphasis inherits italic and still matches")
    func ruleUnderEmphasis() {
        let runs = InlineMapper.map([.emphasis([.text("#x")])], base: ctx.body, ctx: ctx, footnotes: [:])
        guard case .link(let inner, _) = runs.first else { Issue.record("link"); return }
        guard case .text(_, let st) = inner.first else { Issue.record("inner"); return }
        #expect(st.isItalic)
    }

    @Test("hashtag inside a link label is NOT treated as a rule")
    func suppressedInLink() {
        let runs = InlineMapper.map([.link(destination: "u", title: nil, content: [.text("#x")])],
                                    base: ctx.body, ctx: ctx, footnotes: [:])
        guard case .link(let inner, let payload) = runs.first else { Issue.record("link"); return }
        #expect(payload.token == "u")
        #expect(inner.count == 1)
        guard case .text(let s, _) = inner.first else { Issue.record("plain text"); return }
        #expect(s == "#x")
    }

    @Test("inline code span is never treated as a rule")
    func codeNotMatched() {
        let runs = InlineMapper.map([.code("#x")], base: ctx.body, ctx: ctx, footnotes: [:])
        guard case .text(let s, let st) = runs.first else { Issue.record("text"); return }
        #expect(s == "#x")
        #expect(st.isMonospace)
    }

    @Test("with no rules configured, plain text is unchanged")
    func noRulesUnchanged() {
        let plainCtx = StyleContext(.default, .light)
        let runs = InlineMapper.map([.text("#x")], base: plainCtx.body, ctx: plainCtx, footnotes: [:])
        #expect(runs == [.text("#x", plainCtx.body)])
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter InlineMapperRulesTests`
Expected: FAIL — `extra argument 'rules' in call` (StyleContext has no rules param yet).

- [ ] **Step 3a: Add `rules` to `StyleContext`**

In `Sources/Marked/StyleContext.swift` replace lines 5-13:

```swift
struct StyleContext {

    let style: MarkdownStyle
    let palette: MarkdownStyle.Palette
    let rules: [InlineRule]

    init(_ style: MarkdownStyle, _ scheme: MarkdownColorScheme, rules: [InlineRule] = []) {
        self.style = style
        self.palette = scheme == .light ? style.light : style.dark
        self.rules = rules
    }
```

- [ ] **Step 3b: Apply rules in `InlineMapper`**

In `Sources/Marked/InlineMapper.swift` replace the `map` function (lines 4-34):

```swift
    static func map(
        _ nodes: [MarkdownInline],
        base: TextStyle,
        ctx: StyleContext,
        footnotes: [String: Int],
        suppressRules: Bool = false
    ) -> [InlineRun] {
        var runs: [InlineRun] = []
        for node in nodes {
            switch node {
            case .text(let s):
                if suppressRules || ctx.rules.isEmpty {
                    runs.append(.text(s, base))
                } else {
                    runs += InlineRuleEngine.apply(s, rules: ctx.rules, base: base, ctx: ctx)
                }
            case .emphasis(let c):       var st = base; st.isItalic = true;        runs += map(c, base: st, ctx: ctx, footnotes: footnotes, suppressRules: suppressRules)
            case .strong(let c):         var st = base; st.isBold = true;          runs += map(c, base: st, ctx: ctx, footnotes: footnotes, suppressRules: suppressRules)
            case .strikethrough(let c):  var st = base; st.isStrikethrough = true; runs += map(c, base: st, ctx: ctx, footnotes: footnotes, suppressRules: suppressRules)
            case .code(let s):
                var st = base; st.isMonospace = true; st.color = ctx.palette.code; st.fontSize = ctx.style.codeFontSize
                runs.append(.text(s, st))
            case .link(let dest, _, let c):
                runs.append(.link(runs: map(c, base: ctx.linkColored(base), ctx: ctx, footnotes: footnotes, suppressRules: true), payload: LinkPayload(dest)))
            case .image(let src, _, let alt):
                runs.append(.inlineImage(ImageAttachment(source: src, intrinsicSize: ctx.style.inlineImageSize, alt: alt)))
            case .autolink(let url):
                runs.append(.link(runs: [.text(url, ctx.linkColored(base))], payload: LinkPayload(url)))
            case .footnoteReference(let id):
                let n = footnotes[id] ?? 0
                runs.append(.link(runs: [.text("[\(n)]", ctx.linkColored(ctx.footnote))], payload: LinkPayload("footnote:\(id)")))
            case .softBreak: runs.append(.text(" ", base))
            case .hardBreak: runs.append(.lineBreak(hard: true))
            }
        }
        return merge(runs)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter InlineMapperRulesTests`
Expected: PASS (5 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marked/StyleContext.swift Sources/Marked/InlineMapper.swift Tests/MarkedTests/InlineMapperRulesTests.swift
git commit -m "feat(marked): apply custom rules in InlineMapper (suppressed in links/code)"
```

---

### Task 7: Thread `rules:` through `MarkdownRenderer.render`

**Files:**
- Modify: `Sources/Marked/MarkdownRenderer.swift` (both `render` overloads, lines 13-17 and 78-84; `StyleContext` construction at line 24)
- Test: `Tests/MarkedTests/RendererRulesTests.swift`

**Interfaces:**
- Consumes: `StyleContext(_:_:rules:)` (Task 6), `InlineRule` (Task 1).
- Produces: `MarkdownRenderer.render(_:style:colorScheme:rules:)` (both `String` and `MarkdownDocument` overloads). Task 8 calls the `String` overload.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/RendererRulesTests.swift
import Testing
import CoreGraphics
@testable import Marked

@Suite("MarkdownRenderer with custom rules")
struct RendererRulesTests {
    @Test("render threads rules so a hashtag paragraph contains a tappable rule run")
    func hashtagRendered() {
        let rule = InlineRule(id: "hashtag", trigger: "#",
            output: .styledText(InlineDecoration(isBold: true)))
        let doc = MarkdownRenderer.render("#swift", rules: [rule])
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        let hasRuleLink = p.runs.contains { run in
            if case .link(_, let payload) = run {
                return InlineRuleToken.decode(payload.token)?.ruleID == "hashtag"
            }
            return false
        }
        #expect(hasRuleLink)
    }

    @Test("without rules a hashtag stays plain text (no link runs)")
    func noRules() {
        let doc = MarkdownRenderer.render("#swift")
        guard case .paragraph(let p) = doc.blocks.first else { Issue.record("paragraph"); return }
        for run in p.runs {
            if case .link = run { Issue.record("should be no link run"); return }
        }
    }
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter RendererRulesTests`
Expected: FAIL — `extra argument 'rules' in call`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/Marked/MarkdownRenderer.swift`, change the `MarkdownDocument` overload signature (lines 13-17) to add the parameter:

```swift
    static func render(
        _ document: MarkdownDocument,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light,
        rules: [InlineRule] = []
    ) -> TextDocument {
```

In that same function, change the `StyleContext` construction (line 24) to pass rules:

```swift
        let ctx = StyleContext(style, colorScheme, rules: rules)
```

Change the `String` overload (lines 78-84) to accept and forward rules:

```swift
    static func render(
        _ markdown: String,
        style: MarkdownStyle = .default,
        colorScheme: MarkdownColorScheme = .light,
        rules: [InlineRule] = []
    ) -> TextDocument {
        render(MarkdownParser.parse(markdown), style: style, colorScheme: colorScheme, rules: rules)
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter RendererRulesTests`
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add Sources/Marked/MarkdownRenderer.swift Tests/MarkedTests/RendererRulesTests.swift
git commit -m "feat(marked): thread custom rules through MarkdownRenderer.render"
```

---

### Task 8: `MarkdownView` — `rules:` + `onCustomTap:` and full-suite regression

**Files:**
- Modify: `Sources/Marked/MarkdownView.swift` (stored props lines 38-42; init lines 60-72; body lines 76-80; `handleLink` lines 84-95)
- Test: `Tests/MarkedTests/MarkdownViewRulesTests.swift`

**Interfaces:**
- Consumes: `InlineRule`/`CustomInlineTap` (Task 1), `MarkdownRenderer.render(_:style:colorScheme:rules:)` (Task 7), `LinkAction.custom` (Task 2).
- Produces: `MarkdownView.init(_:style:images:isSelectable:rules:onLink:onCustomTap:)` — final public surface.

- [ ] **Step 1: Write the failing test**

```swift
// Tests/MarkedTests/MarkdownViewRulesTests.swift
#if canImport(SwiftUI)
import Testing
import SwiftUI
@testable import Marked

@Suite("MarkdownView custom-rule API")
struct MarkdownViewRulesTests {
    @available(iOS 17, macOS 14, *)
    @MainActor
    @Test("MarkdownView constructs with rules and onCustomTap and renders its body")
    func constructs() {
        var tapped: CustomInlineTap?
        let rule = InlineRule(id: "hashtag", trigger: "#",
            output: .styledText(InlineDecoration(isBold: true)))
        let view = MarkdownView("#swift", rules: [rule],
                                onCustomTap: { tap in tapped = tap })
        _ = view.body          // forces MarkdownRenderer.render(...) with the rules
        #expect(tapped == nil) // no tap has occurred yet
    }
}
#endif
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter MarkdownViewRulesTests`
Expected: FAIL — `argument 'rules' must precede argument 'onCustomTap'` / `extra argument 'rules'`.

- [ ] **Step 3: Write minimal implementation**

In `Sources/Marked/MarkdownView.swift` add two stored properties after line 42 (`private let onLink...`):

```swift
    private let rules: [InlineRule]
    private let onCustomTap: ((CustomInlineTap) -> Void)?
```

Replace the initializer (lines 60-72) with:

```swift
    public init(
        _ markdown: String,
        style: MarkdownStyle = .default,
        images: (any ImageProvider)? = nil,
        isSelectable: Bool = true,
        rules: [InlineRule] = [],
        onLink: ((URL) -> Void)? = nil,
        onCustomTap: ((CustomInlineTap) -> Void)? = nil
    ) {
        self.markdown = markdown
        self.style = style
        self.images = images
        self.isSelectable = isSelectable
        self.rules = rules
        self.onLink = onLink
        self.onCustomTap = onCustomTap
    }
```

Replace `body` (lines 76-80) so render receives the rules:

```swift
    public var body: some View {
        let scheme: MarkdownColorScheme = (colorScheme == .dark) ? .dark : .light
        let doc = MarkdownRenderer.render(markdown, style: style, colorScheme: scheme, rules: rules)
        MarkdownTextView(doc, isSelectable: isSelectable, onLink: { handleLink($0) }, images: images)
    }
```

Replace `handleLink` (lines 84-95) to dispatch `.custom`:

```swift
    private func handleLink(_ payload: LinkPayload) {
        switch MarkdownRenderer.resolveLink(payload.token) {
        case .url(let u):
            if let onLink {
                onLink(u)
            } else {
                openURL(u)
            }
        case .custom(let ruleID, let value):
            onCustomTap?(CustomInlineTap(ruleID: ruleID, value: value))
        case .footnote, .ignore:
            break
        }
    }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter MarkdownViewRulesTests`
Expected: PASS (1 test).

- [ ] **Step 5: Run the FULL suite to confirm no regressions**

Run: `swift test`
Expected: PASS — all previous tests plus the new ones (≥ 524 + new). Zero failures. Confirms the CommonMark parser/conformance baseline is untouched.

- [ ] **Step 6: Commit**

```bash
git add Sources/Marked/MarkdownView.swift Tests/MarkedTests/MarkdownViewRulesTests.swift
git commit -m "feat(marked): MarkdownView rules + onCustomTap public API"
```

---

## Self-Review Notes

**Spec coverage:**
- §4 Public API → Task 1 (`InlineRule`/`InlineDecoration`/`CustomInlineTap`), Task 7 (`render` param), Task 8 (`MarkdownView` params). ✓
- §5 Rule engine (scan, precedence, closing, minBodyLength, boundary, styledText/image forms, includeTrigger) → Task 5. ✓
- §5 recursion under emphasis / suppression in links / code exclusion → Task 6. ✓
- §6 Tap round-trip (`InlineRuleToken`, `LinkAction.custom`, `resolveLink`, `onCustomTap` dispatch) → Task 2 + Task 8. ✓
- §7 Pill (`TextStyle.background` + renderer fill) → Task 3 + Task 4. ✓
- §8 Edge cases — email-vs-mention boundary (Task 5 `leadingBoundary`), code exclusion (Task 6 `codeNotMatched`), link-label suppression (Task 6 `suppressedInLink`); escaping `\#` is a documented limitation (no code/test). ✓
- §9 Testing — per-task tests + full-suite regression in Task 8 Step 5. ✓

**Type consistency:** `InlineRuleEngine.apply(_:rules:base:ctx:)`, `InlineRuleToken.encode(ruleID:value:)`/`decode(_:)`, `StyleContext(_:_:rules:)`, `InlineMapper.map(_:base:ctx:footnotes:suppressRules:)`, `MarkdownRenderer.render(_:style:colorScheme:rules:)`, `MarkdownView.init(_:style:images:isSelectable:rules:onLink:onCustomTap:)`, `markedBackgroundAttributeName` — names are used identically across the tasks that define and consume them.

**No placeholders:** every code step contains complete, compilable code.
