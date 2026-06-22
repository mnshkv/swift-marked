// Inline parser (Pass B): resolves a raw leaf string into `[MarkdownInline]`.
//
// At this wave: plain text + backslash escapes only. Code spans, emphasis,
// links, autolinks, etc. are added by later tasks. Pass B owns all inline
// calls — `BlockParser` does no inline parsing (K1).

struct InlineParser {
    let defs: DefinitionStore

    /// ASCII-punctuation characters a backslash can escape (CommonMark §2.4).
    private static let escapable: Set<Character> = Set("!\"#$%&'()*+,-./:;<=>?@[\\]^_`{|}~")

    /// Parses `text` into inline nodes. At this wave: plain text with backslash
    /// escapes — `\` + ASCII punctuation yields the punctuation char; `\` before
    /// any other char (or at end of input) keeps the literal backslash.
    func parse(_ text: String, depth: Int) -> [MarkdownInline] {
        let chars = Array(text)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, Self.escapable.contains(chars[i + 1]) {
                out.append(chars[i + 1])
                i += 2
            } else {
                out.append(chars[i])
                i += 1
            }
        }
        return out.isEmpty ? [] : [.text(out)]
    }
}
