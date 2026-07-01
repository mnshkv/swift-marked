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
