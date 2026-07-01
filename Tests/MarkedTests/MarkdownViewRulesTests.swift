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
