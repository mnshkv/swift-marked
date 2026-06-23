import Testing
import CoreGraphics
@testable import Marked

@Suite("BlockMapper — list mapping")
struct BlockMapperListTests {

    let ctx = StyleContext(.default, .light)
    var map: ([MarkdownBlock]) -> [Block] {
        { BlockMapper.map($0, ctx: ctx, footnotes: [:]) }
    }

    // MARK: - Task 3.2 tests

    @Test("bullet list, 2 items → .list(marker:.bullet, isTight, items.count==2) each with .paragraph")
    func bulletList() {
        let item = MarkdownListItem(blocks: [.paragraph(content: [.text("x")])])
        let mdList = MarkdownList(kind: .bullet, isTight: true, items: [item, item])
        let blocks = map([.list(mdList)])
        guard case .list(let list) = blocks.first else {
            Issue.record("Expected .list"); return
        }
        #expect(list.marker == .bullet)
        #expect(list.isTight == true)
        #expect(list.items.count == 2)
        for item in list.items {
            guard case .paragraph(_) = item.blocks.first else {
                Issue.record("Expected .paragraph in item"); return
            }
        }
    }

    @Test("ordered list start:3 → .list(marker:.ordered(start:3))")
    func orderedList() {
        let item = MarkdownListItem(blocks: [.paragraph(content: [.text("y")])])
        let mdList = MarkdownList(kind: .ordered(start: 3), isTight: false, items: [item])
        let blocks = map([.list(mdList)])
        guard case .list(let list) = blocks.first else {
            Issue.record("Expected .list"); return
        }
        #expect(list.marker == .ordered(start: 3))
    }

    @Test("nested list: item blocks contain a .list → inner TextDocument.blocks has .list")
    func nestedList() {
        let innerItem = MarkdownListItem(blocks: [.paragraph(content: [.text("inner")])])
        let innerMdList = MarkdownList(kind: .bullet, isTight: true, items: [innerItem])
        let outerItem = MarkdownListItem(blocks: [
            .paragraph(content: [.text("outer")]),
            .list(innerMdList)
        ])
        let outerMdList = MarkdownList(kind: .bullet, isTight: false, items: [outerItem])
        let blocks = map([.list(outerMdList)])
        guard case .list(let outerList) = blocks.first else {
            Issue.record("Expected outer .list"); return
        }
        guard let firstItem = outerList.items.first else {
            Issue.record("Expected outer item"); return
        }
        let hasInnerList = firstItem.blocks.contains {
            if case .list(_) = $0 { return true }
            return false
        }
        #expect(hasInnerList, "Expected nested .list inside item's TextDocument.blocks")
    }
}
