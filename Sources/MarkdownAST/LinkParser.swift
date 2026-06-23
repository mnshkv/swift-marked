// Link/image parsing helpers (Wave 8+): balanced bracket/paren matching and
// destination/title parsing. Pure functions over character arrays.

/// Index of the `]` that closes the `[` at `openAt`, honoring nesting,
/// backslash escapes, and code-span opacity, or nil if unbalanced.
func matchBracket(_ chars: [Character], openAt: Int) -> Int? {
    matchDelimiters(chars, openAt: openAt, open: "[", close: "]")
}

/// Index of the `)` that closes the `(` at `openAt` (same rules as
/// `matchBracket`), or nil if unbalanced.
func matchParen(_ chars: [Character], openAt: Int) -> Int? {
    matchDelimiters(chars, openAt: openAt, open: "(", close: ")")
}

/// Balanced-delimiter scan: counts `open`/`close` depth, skipping `\`-escaped
/// characters and treating backtick code spans as opaque.
private func matchDelimiters(_ chars: [Character], openAt: Int, open: Character, close: Character) -> Int? {
    guard openAt < chars.count, chars[openAt] == open else { return nil }
    var depth = 0
    var i = openAt
    while i < chars.count {
        let c = chars[i]
        if c == "\\" {
            i += 2 // skip the escaped character
            continue
        }
        if c == "`" {
            var n = 0
            while i + n < chars.count, chars[i + n] == "`" { n += 1 }
            if let close = closingBacktickRun(chars, from: i + n, length: n) {
                i = close + n // jump past an opaque code span
            } else {
                i += n // unmatched run — treat the backticks as literal
            }
            continue
        }
        if c == open {
            depth += 1
        } else if c == close {
            depth -= 1
            if depth == 0 { return i }
        }
        i += 1
    }
    return nil
}

/// Index of a closing backtick run of exactly `n` backticks at or after `start`
/// (runs of other lengths are content), or nil.
func closingBacktickRun(_ chars: [Character], from start: Int, length n: Int) -> Int? {
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
