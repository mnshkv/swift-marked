import Testing
import CoreGraphics
@testable import MarkdownTextEngine

@Suite("Table width")
struct TableWidthTests {
    // Regression: with short content and a wide available width, the table box
    // must hug its columns (width == sum of column widths), not stretch to the
    // full available width and leave an empty boxed area on the right.
    @Test("table box hugs its columns instead of filling the full width")
    func tableHugsColumns() {
        let s = TextStyle(fontSize: 15, color: .black)
        let table = Table(
            alignments: [.leading, .leading],
            header: [[.text("A", s)], [.text("B", s)]],
            rows: [[[.text("x", s)], [.text("y", s)]]],
            cellStyle: s
        )
        let available: CGFloat = 400
        let columnsWidth = tableColumnWidths(table, available: available).reduce(0, +)

        let frame = layoutTable(table, width: available, origin: .zero)
        guard case .table(let rect, _, _, _, _) = frame else {
            Issue.record("expected a table frame")
            return
        }
        #expect(rect.width < available)                 // narrower than available
        #expect(abs(rect.width - columnsWidth) < 0.5)   // exactly the columns' width
    }
}
