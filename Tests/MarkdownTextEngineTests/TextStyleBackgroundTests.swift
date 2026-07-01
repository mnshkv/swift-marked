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
