import CoreGraphics

enum InlineMapper {
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

    static func merge(_ runs: [InlineRun]) -> [InlineRun] {
        var result: [InlineRun] = []
        for run in runs {
            if case .text(let newStr, let newStyle) = run,
               case .text(let lastStr, let lastStyle) = result.last,
               newStyle == lastStyle {
                result[result.count - 1] = .text(lastStr + newStr, lastStyle)
            } else {
                result.append(run)
            }
        }
        return result
    }
}
