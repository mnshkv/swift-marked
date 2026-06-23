import Testing
import CoreGraphics
@testable import Marked

@Suite("MarkdownStyle")
struct MarkdownStyleTests {
    @Test("default has 6 heading sizes, descending, h4 == body")
    func defaults() {
        let s = MarkdownStyle.default
        #expect(s.headingSizes.count == 6)
        #expect(s.headingSizes[0] > s.headingSizes[5])
        #expect(s.headingSizes[3] == s.baseFontSize)        // h4 == body (17)
        #expect(s.baseFontSize == 17)
        #expect(s.light.link != s.light.text)               // distinct semantic colors
    }
}
