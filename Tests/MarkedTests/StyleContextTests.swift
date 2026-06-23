import Testing
import CoreGraphics
@testable import Marked

@Suite("StyleContext")
struct StyleContextTests {
    @Test("light vs dark resolve different text colors; heading is bold and bigger")
    func resolves() {
        let light = StyleContext(.default, .light)
        let dark = StyleContext(.default, .dark)
        #expect(light.body.color != dark.body.color)
        #expect(light.heading(1).isBold)
        #expect(light.heading(1).fontSize > light.body.fontSize)
        #expect(light.heading(9).fontSize == light.heading(6).fontSize)  // clamped
    }

    @Test("headingSizes shorter than 6 — no trap; returns last element as fallback")
    func headingSizesShortFallback() {
        var style = MarkdownStyle.default
        style.headingSizes = [20]
        let ctx = StyleContext(style, .light)
        // Level 1 → index 0 → exists → 20
        #expect(ctx.heading(1).fontSize == 20)
        // Level 3 → index 2 → out of bounds → fallback to last (20)
        let fallback = ctx.heading(3)
        #expect(fallback.fontSize.isFinite)
        #expect(fallback.fontSize == 20)
        // Level 6 → index 5 → out of bounds → fallback to last (20)
        #expect(ctx.heading(6).fontSize == 20)
    }

    @Test("headingSizes empty — no trap; falls back to baseFontSize")
    func headingSizesEmptyFallback() {
        var style = MarkdownStyle.default
        style.headingSizes = []
        let ctx = StyleContext(style, .light)
        let result = ctx.heading(1)
        #expect(result.fontSize.isFinite)
        #expect(result.fontSize == style.baseFontSize)
    }
}
