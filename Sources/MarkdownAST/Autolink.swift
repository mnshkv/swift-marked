// CommonMark autolinks (Wave 9): `<scheme:...>` URIs and `<local@domain>` emails.
// GFM bare/extended autolinks are a later task.

/// Parses a CommonMark autolink `<...>` at `chars[start]` (`<`), returning the
/// `.autolink` node and the index past `>`, or nil. The content must be an
/// absolute URI (`scheme:rest`) or an email address, with no whitespace or `<`.
func parseAutolink(_ chars: [Character], from start: Int) -> (MarkdownInline, Int)? {
    guard start < chars.count, chars[start] == "<" else { return nil }
    var j = start + 1
    var content = ""
    while j < chars.count, chars[j] != ">" {
        let c = chars[j]
        if c.isWhitespace || c == "<" { return nil }
        content.append(c)
        j += 1
    }
    guard j < chars.count, chars[j] == ">", !content.isEmpty else { return nil }
    guard isAbsoluteURI(content) || isEmailAddress(content) else { return nil }
    return (.autolink(url: content), j + 1)
}

/// `scheme:rest` where the scheme starts with an ASCII letter followed by ASCII
/// letters/digits/`+`/`.`/`-`, and `rest` is non-empty.
private func isAbsoluteURI(_ s: String) -> Bool {
    guard let colon = s.firstIndex(of: ":") else { return false }
    let scheme = s[s.startIndex..<colon]
    guard s.index(after: colon) < s.endIndex else { return false } // non-empty rest
    guard let first = scheme.first, first.isASCII, first.isLetter else { return false }
    return scheme.allSatisfy { ch in
        ch.isASCII && (ch.isLetter || ch.isNumber || ch == "+" || ch == "." || ch == "-")
    }
}

/// `local@domain.tld`: exactly one `@`, non-empty sides, and a dot in the domain
/// that is not at either end.
private func isEmailAddress(_ s: String) -> Bool {
    let parts = s.split(separator: "@", omittingEmptySubsequences: false)
    guard parts.count == 2 else { return false }
    let local = parts[0]
    let domain = parts[1]
    guard !local.isEmpty, !domain.isEmpty, domain.contains("."),
          domain.first != ".", domain.last != "." else { return false }
    return true
}
