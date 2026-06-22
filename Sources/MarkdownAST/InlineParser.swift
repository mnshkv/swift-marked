// Inline parser (Pass B): resolves a raw leaf string into `[MarkdownInline]`.
//
// At this wave: plain text + backslash escapes only. Code spans, emphasis,
// links, autolinks, etc. are added by later tasks. Pass B owns all inline
// calls — `BlockParser` does no inline parsing (K1).

struct InlineParser {
    let defs: DefinitionStore

    /// ASCII-punctuation characters a backslash can escape (CommonMark §2.4).
    private static let escapable: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    /// Parses `text` into inline nodes: plain text with backslash escapes, GFM
    /// footnote references (`[^id]`), and full reference links (`[text][label]`)
    /// resolved against `defs`. Unresolved brackets stay literal text.
    func parse(_ text: String, depth: Int) -> [MarkdownInline] {
        let chars = Array(text)
        var result: [MarkdownInline] = []
        var buf = ""
        func flushText() {
            if !buf.isEmpty { result.append(.text(buf)); buf = "" }
        }
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c == "\\", i + 1 < chars.count, Self.escapable.contains(chars[i + 1]) {
                buf.append(chars[i + 1])
                i += 2
                continue
            }
            if c == "[" {
                if i + 1 < chars.count, chars[i + 1] == "^",
                   let (id, end) = scanFootnoteRef(chars, from: i), defs.hasFootnote(id) {
                    flushText()
                    result.append(.footnoteReference(id: id))
                    i = end
                    continue
                }
                if let (linkText, label, end) = scanReferenceLink(chars, from: i),
                   let def = defs.link(for: label) {
                    flushText()
                    result.append(.link(destination: def.destination, title: def.title,
                                        content: parse(linkText, depth: depth + 1)))
                    i = end
                    continue
                }
            }
            buf.append(c)
            i += 1
        }
        flushText()
        return result
    }

    /// Scans a footnote reference `[^id]` at `chars[start]` (`[`), returning the
    /// id and the index just past the closing `]`, or nil if malformed.
    private func scanFootnoteRef(_ chars: [Character], from start: Int) -> (String, Int)? {
        var j = start + 2 // skip `[^`
        var id = ""
        while j < chars.count, chars[j] != "]" {
            if chars[j] == "[" { return nil }
            id.append(chars[j])
            j += 1
        }
        guard j < chars.count, !id.isEmpty else { return nil }
        return (id, j + 1)
    }

    /// Scans a full reference link `[text][label]` at `chars[start]` (`[`),
    /// returning the link text, label, and index past the final `]`, or nil.
    private func scanReferenceLink(_ chars: [Character], from start: Int) -> (String, String, Int)? {
        var j = start + 1
        var text = ""
        while j < chars.count, chars[j] != "]" {
            if chars[j] == "[" { return nil }
            text.append(chars[j])
            j += 1
        }
        guard j < chars.count else { return nil }
        j += 1 // past first `]`
        guard j < chars.count, chars[j] == "[" else { return nil }
        j += 1
        var label = ""
        while j < chars.count, chars[j] != "]" {
            if chars[j] == "[" { return nil }
            label.append(chars[j])
            j += 1
        }
        guard j < chars.count else { return nil }
        return (text, label, j + 1)
    }
}
