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
            if c == "`" {
                // Code span: an opening backtick run is closed by a run of equal
                // length; content is verbatim (no escapes). An unmatched run is
                // literal text.
                var n = 0
                while i + n < chars.count, chars[i + n] == "`" { n += 1 }
                if let close = findClosingBacktickRun(chars, from: i + n, length: n) {
                    flushText()
                    result.append(.code(codeSpanContent(chars, from: i + n, to: close)))
                    i = close + n
                } else {
                    buf.append(String(repeating: "`", count: n))
                    i += n
                }
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

    /// Finds the index of a closing backtick run of exactly `n` backticks at or
    /// after `start` (runs of other lengths are skipped as content), or nil.
    private func findClosingBacktickRun(_ chars: [Character], from start: Int, length n: Int) -> Int? {
        var j = start
        while j < chars.count {
            guard chars[j] == "`" else { j += 1; continue }
            var m = 0
            while j + m < chars.count, chars[j + m] == "`" { m += 1 }
            if m == n { return j }
            j += m
        }
        return nil
    }

    /// Code-span content `chars[start..<end]`, stripping one leading and one
    /// trailing space iff both edges are spaces and it is not all spaces (§6.3).
    private func codeSpanContent(_ chars: [Character], from start: Int, to end: Int) -> String {
        var content = String(chars[start..<end])
        if content.count >= 2, content.first == " ", content.last == " ",
           !content.allSatisfy({ $0 == " " }) {
            content = String(content.dropFirst().dropLast())
        }
        return content
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
