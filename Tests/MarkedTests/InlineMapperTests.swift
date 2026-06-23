import Testing
import CoreGraphics
@testable import Marked

@Suite("InlineMapper")
struct InlineMapperTests {

    let ctx = StyleContext(.default, .light)
    var m: ([MarkdownInline]) -> [InlineRun] {
        { InlineMapper.map($0, base: ctx.body, ctx: ctx, footnotes: [:]) }
    }

    // MARK: - Task 2.1 tests

    @Test("emphasis → italic run")
    func emphasis() {
        let runs = m([.emphasis([.text("a")])])
        guard case .text(let s, let style) = runs.first else {
            Issue.record("Expected a .text run"); return
        }
        #expect(s == "a")
        #expect(style.isItalic)
    }

    @Test("strong(emphasis) → bold AND italic")
    func strongEmphasis() {
        let runs = m([.strong([.emphasis([.text("a")])])])
        guard case .text(let s, let style) = runs.first else {
            Issue.record("Expected a .text run"); return
        }
        #expect(s == "a")
        #expect(style.isBold)
        #expect(style.isItalic)
    }

    @Test("strikethrough → isStrikethrough")
    func strikethrough() {
        let runs = m([.strikethrough([.text("a")])])
        guard case .text(_, let style) = runs.first else {
            Issue.record("Expected a .text run"); return
        }
        #expect(style.isStrikethrough)
    }

    @Test("code → monospace + code color + code font size")
    func inlineCode() {
        let runs = m([.code("x")])
        guard case .text(let s, let style) = runs.first else {
            Issue.record("Expected a .text run"); return
        }
        #expect(s == "x")
        #expect(style.isMonospace)
        #expect(style.color == ctx.palette.code)
        #expect(style.fontSize == ctx.style.codeFontSize)
    }

    @Test("link → .link with correct payload and link-colored run")
    func link() {
        let runs = m([.link(destination: "u", title: nil, content: [.text("t")])])
        guard case .link(let linkRuns, let payload) = runs.first else {
            Issue.record("Expected a .link run"); return
        }
        #expect(payload.token == "u")
        guard case .text(let s, let style) = linkRuns.first else {
            Issue.record("Expected inner .text run"); return
        }
        #expect(s == "t")
        #expect(style.color == ctx.palette.link)
    }

    @Test("autolink → .link payload equals URL, run text equals URL")
    func autolink() {
        let runs = m([.autolink(url: "http://x")])
        guard case .link(let linkRuns, let payload) = runs.first else {
            Issue.record("Expected a .link run"); return
        }
        #expect(payload.token == "http://x")
        guard case .text(let s, _) = linkRuns.first else {
            Issue.record("Expected inner .text run"); return
        }
        #expect(s == "http://x")
    }

    @Test("image → .inlineImage with source, alt, and inlineImageSize")
    func image() {
        let runs = m([.image(source: "s", title: nil, alt: "a")])
        guard case .inlineImage(let attachment) = runs.first else {
            Issue.record("Expected an .inlineImage run"); return
        }
        #expect(attachment.source == "s")
        #expect(attachment.alt == "a")
        #expect(attachment.intrinsicSize == ctx.style.inlineImageSize)
    }

    @Test("footnoteReference → .link text '[3]', payload 'footnote:fn'")
    func footnoteReference() {
        let runs = InlineMapper.map(
            [.footnoteReference(id: "fn")],
            base: ctx.body,
            ctx: ctx,
            footnotes: ["fn": 3]
        )
        guard case .link(let linkRuns, let payload) = runs.first else {
            Issue.record("Expected a .link run"); return
        }
        #expect(payload.token == "footnote:fn")
        guard case .text(let s, _) = linkRuns.first else {
            Issue.record("Expected inner .text run"); return
        }
        #expect(s == "[3]")
    }

    @Test("softBreak → space text; hardBreak → lineBreak(hard:true)")
    func breaks() {
        let runs = m([.softBreak, .hardBreak])
        guard runs.count == 2 else {
            Issue.record("Expected 2 runs, got \(runs.count)"); return
        }
        guard case .text(let s, _) = runs[0] else {
            Issue.record("Expected .text for softBreak"); return
        }
        #expect(s == " ")
        guard case .lineBreak(let hard) = runs[1] else {
            Issue.record("Expected .lineBreak for hardBreak"); return
        }
        #expect(hard)
    }

    // MARK: - Task 2.2 merge tests

    @Test("two adjacent same-style text runs merge into one")
    func mergeAdjacentSameStyle() {
        let runs = m([.text("a"), .text("b")])
        #expect(runs.count == 1)
        guard case .text(let s, _) = runs.first else {
            Issue.record("Expected a .text run"); return
        }
        #expect(s == "ab")
    }

    @Test("different styles are not merged")
    func noDifferentStyleMerge() {
        let runs = m([.text("a"), .emphasis([.text("b")])])
        #expect(runs.count == 2)
    }

    @Test("code then text — different styles, not merged")
    func noCodeTextMerge() {
        let runs = m([.code("x"), .text("y")])
        #expect(runs.count == 2)
    }
}
