import Testing
@testable import MarkdownAST

@Suite("GFM task list items (Pass A raw leaves)")
struct TaskListTests {
    @Test("unchecked task item")
    func uncheckedTask() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- [ ] todo"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "todo")], task: .unchecked),
            ])),
        ])
    }

    @Test("checked task item (lowercase x)")
    func checkedTaskLower() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- [x] done"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "done")], task: .checked),
            ])),
        ])
    }

    @Test("checked task item (uppercase X)")
    func checkedTaskUpper() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- [X] done"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "done")], task: .checked),
            ])),
        ])
    }

    @Test("extra spaces after the checkbox are stripped")
    func extraSpacesStripped() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- [x]  done"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "done")], task: .checked),
            ])),
        ])
    }

    @Test("a normal item has no task state")
    func normalItemNoTask() {
        let out = BlockParser(defs: DefinitionStore()).parse(["- normal"], depth: 0)
        #expect(out == [
            .list(RawList(kind: .bullet, isTight: true, items: [
                RawListItem(blocks: [.paragraph(raw: "normal")], task: nil),
            ])),
        ])
    }
}
