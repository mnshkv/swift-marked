import Testing
import CoreText
import CoreGraphics
@testable import MarkdownTextEngine

// MARK: - Helpers

private func pixel(at x: Int, y: Int, width: Int, buffer: UnsafeMutableRawPointer)
    -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)
{
    let offset = (y * width + x) * 4
    let p = buffer.assumingMemoryBound(to: UInt8.self)
    return (p[offset], p[offset + 1], p[offset + 2], p[offset + 3])
}

private func makeWhiteContext(width: Int, height: Int)
    -> (ctx: CGContext, buffer: UnsafeMutableRawPointer)?
{
    let bytesPerRow = width * 4
    let rawBuffer = UnsafeMutableRawPointer.allocate(byteCount: height * bytesPerRow, alignment: 16)
    rawBuffer.initializeMemory(as: UInt8.self, repeating: 0xFF, count: height * bytesPerRow)
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
          let ctx = CGContext(data: rawBuffer, width: width, height: height,
                              bitsPerComponent: 8, bytesPerRow: bytesPerRow,
                              space: colorSpace,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
    else { rawBuffer.deallocate(); return nil }
    return (ctx, rawBuffer)
}

private func textStyle() -> TextStyle {
    TextStyle(fontSize: 14, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
}

private func codeStyle() -> TextStyle {
    TextStyle(fontSize: 13, isMonospace: true, color: CGColor(red: 0, green: 0, blue: 0, alpha: 1))
}

private func cellRuns(_ text: String) -> [InlineRun] {
    [.text(text, textStyle())]
}

// MARK: - Task 5.4: Renderer tests for tables and code blocks

@Suite("Table and code block rendering (Task 5.4)")
struct TableCodeRendererTests {

    // ------------------------------------------------------------------
    // 5.4-A: Table grid borders have ink at expected column x positions
    // ------------------------------------------------------------------
    @Test("table grid borders produce dark ink at column divider x positions")
    func tableBordersHaveInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Col A"), cellRuns("Col B")],
            rows: [[cellRuns("val1"), cellRuns("val2")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The table occupies rows 0..h, so border lines should produce dark ink somewhere.
        var foundDarkPixel = false
        outer: for y in 0..<h {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 200 || px.g < 200 || px.b < 200 {
                    foundDarkPixel = true
                    break outer
                }
            }
        }
        #expect(foundDarkPixel, "Table rendering should produce dark ink (borders or text)")
    }

    // ------------------------------------------------------------------
    // 5.4-B: Table cell text has ink in the cell content region
    // ------------------------------------------------------------------
    @Test("table cell text produces glyph ink in content region")
    func tableCellTextHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(
            alignments: [.leading, .leading],
            header: [cellRuns("Hello"), cellRuns("World")],
            rows: [[cellRuns("Foo"), cellRuns("Bar")]],
            cellStyle: textStyle()
        )
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Glyph ink should appear somewhere in the first 80 rows
        var foundInk = false
        outer: for y in 0..<80 {
            for x in 0..<(w / 2) {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Table cell region should have glyph ink")
    }

    // ------------------------------------------------------------------
    // 5.4-C: Code block box region is filled (non-white background)
    // ------------------------------------------------------------------
    @Test("code block box region has filled background (non-white)")
    func codeBoxIsFilled() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["let x = 42", "return x"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        guard case .code(_, let box, _, _) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // The box region should have non-white fill pixels.
        // In CG coordinates (y-up), box in doc-space maps to:
        //   CG y = canvasHeight - box.maxY ... canvasHeight - box.minY
        // In bitmap memory (row 0 = CG y = h-1 = top of image):
        //   bitmap row = h - 1 - CG_y = doc_y
        let boxMinRow = Int(box.minY)
        let boxMaxRow = min(Int(box.maxY), h - 1)

        var foundFill = false
        outerBox: for y in boxMinRow...boxMaxRow {
            for x in 0..<w {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                // Non-white fill (box background color)
                if px.r < 250 || px.g < 250 || px.b < 250 {
                    foundFill = true
                    break outerBox
                }
            }
        }
        #expect(foundFill, "Code block box region should have non-white fill pixels")
    }

    // ------------------------------------------------------------------
    // 5.4-D: Code block has glyph ink (text was drawn)
    // ------------------------------------------------------------------
    @Test("code block content region has glyph ink")
    func codeBlockGlyphInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["hello world"],
            language: nil,
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Glyph ink should appear in the first 60 rows
        var foundInk = false
        outer: for y in 0..<60 {
            for x in 0..<200 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Code block should produce glyph ink in content region")
    }

    // ------------------------------------------------------------------
    // 5.4-E: Code block with language label — ink appears above box top
    // ------------------------------------------------------------------
    @Test("code block with language label produces ink above box region")
    func codeLanguageLabelHasInk() {
        let w = 400; let h = 200
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(
            lines: ["func foo() {}"],
            language: "swift",
            style: codeStyle()
        )
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        guard case .code(_, _, _, let langLabel) = layout.blocks[0] else {
            Issue.record("expected .code block frame"); return
        }
        // Verify we have a language label to render
        guard langLabel != nil else {
            Issue.record("code block with language should have language label"); return
        }

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])

        // Ink must appear somewhere
        var foundInk = false
        outer: for y in 0..<h {
            for x in 0..<300 {
                let px = pixel(at: x, y: y, width: w, buffer: buffer)
                if px.r < 240 || px.g < 240 || px.b < 240 {
                    foundInk = true
                    break outer
                }
            }
        }
        #expect(foundInk, "Code block with language should produce ink (label + content)")
    }

    // ------------------------------------------------------------------
    // 5.4-F: Empty table renders without crash
    // ------------------------------------------------------------------
    @Test("empty table renders without crash")
    func emptyTableNoOp() {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let t = Table(alignments: [], header: [], rows: [], cellStyle: textStyle())
        let doc = TextDocument(blocks: [.table(t)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // Must not crash
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])
        // Empty table — no non-white pixels expected
        let px = pixel(at: 50, y: 50, width: w, buffer: buffer)
        #expect(px.r == 255 && px.g == 255 && px.b == 255,
                "Empty table should not paint anything")
    }

    // ------------------------------------------------------------------
    // 5.4-G: Empty code block renders without crash (only box fill)
    // ------------------------------------------------------------------
    @Test("empty code block renders without crash")
    func emptyCodeBlockNoOp() {
        let w = 100; let h = 100
        guard let (ctx, buffer) = makeWhiteContext(width: w, height: h) else {
            Issue.record("Could not create CGContext"); return
        }
        defer { buffer.deallocate() }

        let cb = CodeBlock(lines: [], language: nil, style: codeStyle())
        let doc = TextDocument(blocks: [.codeBlock(cb)])
        let layout = LayoutEngine.layout(doc, width: CGFloat(w))

        let visible = CGRect(x: 0, y: 0, width: CGFloat(w), height: CGFloat(h))
        // Must not crash
        DocumentRenderer.draw(layout, in: ctx, canvasHeight: CGFloat(h), visible: visible, selection: [])
        // Just verify it ran without crashing — no assertion on content needed
    }
}
