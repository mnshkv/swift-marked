#if canImport(AppKit)
import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("AppKit cull-rect conversion")
struct CullingConversionTests {
    // Regression: NSView's dirtyRect is y-up; the renderer culls block frames in
    // document space (y-down). A partial dirtyRect that is not converted culls
    // the wrong blocks, making whole sections vanish inside a scroll view.
    @Test("y-up dirty rect converts to document y-down")
    func conversion() {
        let height: CGFloat = 1000
        // Top of the view (high y, y-up) maps to the document top (low y, y-down).
        let top = TextEngineView.documentVisibleRect(
            CGRect(x: 0, y: 900, width: 400, height: 100), boundsHeight: height)
        #expect(top.minY == 0)
        #expect(top.maxY == 100)
        // Bottom of the view (low y) maps to the document bottom (high y).
        let bottom = TextEngineView.documentVisibleRect(
            CGRect(x: 0, y: 0, width: 400, height: 100), boundsHeight: height)
        #expect(bottom.minY == 900)
        #expect(bottom.maxY == 1000)
    }
}
#endif
