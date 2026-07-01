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

    @Test("selection highlight paints over a pilled run, not beneath it")
    func selectionPaintsOverPill() throws {
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

        // Selection rect covers the same top-left zone that carries the pill.
        let selectionRect = CGRect(x: 0, y: 0, width: 60, height: 30)
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h),
                              visible: CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h)),
                              selection: [selectionRect])

        // Correct z-order (pill -> selection -> glyphs): the opaque green pill
        // is drawn first, then the system-blue-at-30%-alpha selection tint is
        // blended on top of it. Blending selection (0.20, 0.47, 0.97 @ 0.30)
        // over opaque green (0, 1, 0) yields approximately (15, 210, 74):
        // red stays low (~15, since the pill contributed no red), while blue
        // rises from 0 (pure pill, no tint) to ~74.
        //
        // We require BOTH r < 50 (rules out selection-over-white pixels
        // outside the pill's footprint — those blend to ~(194, 214, 252), a
        // high red channel) AND b > 50 (rules out plain, untinted pill green
        // (0, 255, 0), plain black glyph ink, AND stray anti-aliased edge
        // pixels at the pill's rounded corners — empirically those reach at
        // most b ~= 32, well under this threshold). Verified empirically (by
        // temporarily reverting the pre-pass, i.e. re-introducing the
        // pre-fix bug) that with the pre-pass removed NO pixel in the scanned
        // region satisfies both conditions (every pill pixel is pure opaque
        // green, b == 0), while with the pre-pass present hundreds of pixels
        // satisfy both (b ~= 74). This makes the assertion a reliable guard
        // against the z-order regressing.
        var foundBlendedHighlight = false
        outer: for y in 0..<20 {
            for x in 0..<60 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if Int(px.r) < 50 && Int(px.b) > 50 {
                    foundBlendedHighlight = true
                    break outer
                }
            }
        }
        #expect(foundBlendedHighlight, "Expected the selection tint to be visible over the pill background")
    }
}
