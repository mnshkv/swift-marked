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
