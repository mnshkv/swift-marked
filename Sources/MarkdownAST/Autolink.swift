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

// MARK: - GFM extended (bare) autolinks

/// A GFM bare autolink may start only at the document start or after whitespace
/// or one of `*_~(`.
func isAutolinkBoundary(_ chars: [Character], _ i: Int) -> Bool {
    if i == 0 { return true }
    let p = chars[i - 1]
    return p.isWhitespace || p == "(" || p == "*" || p == "_" || p == "~"
}

private let autolinkTrailingPunctuation: Set<Character> = Set("?!.,:*_~")

/// Scans a GFM bare URL (`http://`, `https://`, or `www.` prefix) at `start`,
/// trimming trailing punctuation and unmatched `)`. Returns the URL text and the
/// index just past it, or nil.
func scanBareURL(_ chars: [Character], from start: Int) -> (url: String, end: Int)? {
    let prefixes = [Array("https://"), Array("http://"), Array("www.")]
    guard prefixes.contains(where: { p in
        start + p.count <= chars.count && Array(chars[start..<(start + p.count)]) == p
    }) else { return nil }

    var end = start
    while end < chars.count, !chars[end].isWhitespace, chars[end] != "<" { end += 1 }

    var changed = true
    while changed, end > start {
        changed = false
        let last = chars[end - 1]
        if autolinkTrailingPunctuation.contains(last) {
            end -= 1; changed = true
        } else if last == ")" {
            let slice = chars[start..<end]
            if slice.filter({ $0 == ")" }).count > slice.filter({ $0 == "(" }).count {
                end -= 1; changed = true
            }
        }
    }

    let url = String(chars[start..<end])
    guard url.contains("."), end > start else { return nil }
    return (url, end)
}

private func isEmailLocalChar(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "_" || c == "+" || c == "-")
}

private func isEmailDomainChar(_ c: Character) -> Bool {
    c.isASCII && (c.isLetter || c.isNumber || c == "." || c == "-")
}

/// Scans a GFM bare email ending at the `@` in `chars[at]`: the local part is the
/// trailing run of `buf`, the domain follows `@`. Returns the full address, how
/// many trailing chars of `buf` form the local part, and the index past the
/// domain — or nil if it is not a valid bare email.
func scanBareEmail(buf: [Character], chars: [Character], at: Int) -> (email: String, localLen: Int, end: Int)? {
    var localLen = 0
    var k = buf.count - 1
    while k >= 0, isEmailLocalChar(buf[k]) { localLen += 1; k -= 1 }
    guard localLen > 0 else { return nil }
    let local = String(buf[(buf.count - localLen)...])

    var j = at + 1
    var domain = ""
    while j < chars.count, isEmailDomainChar(chars[j]) { domain.append(chars[j]); j += 1 }
    while let last = domain.last, autolinkTrailingPunctuation.contains(last) {
        domain.removeLast(); j -= 1
    }
    guard !domain.isEmpty, domain.contains("."), domain.first != ".", domain.last != "." else { return nil }
    return (local + "@" + domain, localLen, j)
}
