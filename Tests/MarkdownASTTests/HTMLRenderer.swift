import MarkdownAST

// Test-only AST -> HTML renderer + HTML normalizer for the CommonMark/GFM
// conformance harness (W1-T26a/b). Not part of the shipped library.

/// Renders a parsed document to HTML approximating CommonMark output.
func astToHTML(_ doc: MarkdownDocument) -> String {
    blocksToHTML(doc.blocks, tight: false)
}

private func blocksToHTML(_ blocks: [MarkdownBlock], tight: Bool) -> String {
    var out = ""
    for block in blocks {
        out += blockToHTML(block, tight: tight)
    }
    return out
}

private func blockToHTML(_ block: MarkdownBlock, tight: Bool) -> String {
    switch block {
    case .heading(let level, let content):
        return "<h\(level)>\(inlinesToHTML(content))</h\(level)>\n"
    case .paragraph(let content):
        if tight { return inlinesToHTML(content) }
        return "<p>\(inlinesToHTML(content))</p>\n"
    case .thematicBreak:
        return "<hr />\n"
    case .codeBlock(let language, let code):
        let cls = language.flatMap { $0.isEmpty ? nil : " class=\"language-\($0)\"" } ?? ""
        return "<pre><code\(cls)>\(htmlEscape(code))\n</code></pre>\n"
    case .blockQuote(let blocks):
        return "<blockquote>\n\(blocksToHTML(blocks, tight: false))</blockquote>\n"
    case .list(let list):
        return listToHTML(list)
    case .table(let table):
        return tableToHTML(table)
    case .definitionList:
        return "" // non-standard extension, excluded from conformance
    }
}

private func listToHTML(_ list: MarkdownList) -> String {
    let tag: String
    var openAttr = ""
    switch list.kind {
    case .bullet: tag = "ul"
    case .ordered(let start):
        tag = "ol"
        if start != 1 { openAttr = " start=\"\(start)\"" }
    }
    var out = "<\(tag)\(openAttr)>\n"
    for item in list.items {
        out += "<li>"
        if let task = item.task {
            out += "<input \(task == .checked ? "checked " : "")disabled=\"\" type=\"checkbox\"> "
        }
        let inner = blocksToHTML(item.blocks, tight: list.isTight)
        if list.isTight {
            out += inner
        } else {
            out += "\n" + inner
        }
        out += "</li>\n"
    }
    out += "</\(tag)>\n"
    return out
}

private func tableToHTML(_ table: MarkdownTable) -> String {
    func cell(_ inlines: [MarkdownInline], header: Bool, align: MarkdownTable.Alignment) -> String {
        let tag = header ? "th" : "td"
        let style: String
        switch align {
        case .left: style = " align=\"left\""
        case .center: style = " align=\"center\""
        case .right: style = " align=\"right\""
        case .none: style = ""
        }
        return "<\(tag)\(style)>\(inlinesToHTML(inlines))</\(tag)>"
    }
    func align(_ i: Int) -> MarkdownTable.Alignment {
        i < table.alignments.count ? table.alignments[i] : .none
    }
    var out = "<table>\n<thead>\n<tr>\n"
    for (i, h) in table.header.enumerated() { out += cell(h, header: true, align: align(i)) + "\n" }
    out += "</tr>\n</thead>\n"
    if !table.rows.isEmpty {
        out += "<tbody>\n"
        for row in table.rows {
            out += "<tr>\n"
            for (i, c) in row.enumerated() { out += cell(c, header: false, align: align(i)) + "\n" }
            out += "</tr>\n"
        }
        out += "</tbody>\n"
    }
    out += "</table>\n"
    return out
}

private func inlinesToHTML(_ inlines: [MarkdownInline]) -> String {
    var out = ""
    for inline in inlines { out += inlineToHTML(inline) }
    return out
}

private func inlineToHTML(_ inline: MarkdownInline) -> String {
    switch inline {
    case .text(let t): return htmlEscape(t)
    case .emphasis(let c): return "<em>\(inlinesToHTML(c))</em>"
    case .strong(let c): return "<strong>\(inlinesToHTML(c))</strong>"
    case .strikethrough(let c): return "<del>\(inlinesToHTML(c))</del>"
    case .code(let code): return "<code>\(htmlEscape(code))</code>"
    case .link(let dest, let title, let content):
        let t = title.map { " title=\"\(htmlEscape($0))\"" } ?? ""
        return "<a href=\"\(htmlEscapeURL(dest))\"\(t)>\(inlinesToHTML(content))</a>"
    case .image(let src, let title, let alt):
        let t = title.map { " title=\"\(htmlEscape($0))\"" } ?? ""
        return "<img src=\"\(htmlEscapeURL(src))\" alt=\"\(htmlEscape(alt))\"\(t) />"
    case .autolink(let url):
        let isEmail = !url.contains(":") && url.contains("@")
        let href = isEmail ? "mailto:\(url)" : url
        return "<a href=\"\(htmlEscapeURL(href))\">\(htmlEscape(url))</a>"
    case .footnoteReference(let id):
        return "<sup class=\"footnote-ref\"><a href=\"#fn-\(id)\" id=\"fnref-\(id)\">\(htmlEscape(id))</a></sup>"
    case .softBreak: return "\n"
    case .hardBreak: return "<br />\n"
    }
}

func htmlEscape(_ s: String) -> String {
    var out = ""
    for c in s {
        switch c {
        case "&": out += "&amp;"
        case "<": out += "&lt;"
        case ">": out += "&gt;"
        case "\"": out += "&quot;"
        default: out.append(c)
        }
    }
    return out
}

private func htmlEscapeURL(_ s: String) -> String {
    // Minimal: escape the HTML-significant characters in an attribute value.
    htmlEscape(s)
}

/// Normalizes HTML for comparison: trims, and collapses insignificant
/// whitespace between block-level tags (outside `<pre>`), so block layout
/// differences do not cause spurious mismatches.
func normalizeHTML(_ html: String) -> String {
    let chars = Array(html)
    var out = ""
    var i = 0
    var inPre = false
    while i < chars.count {
        if !inPre, chars[i].isWhitespace {
            // collapse whitespace that sits between two tags to nothing,
            // otherwise to a single space.
            var j = i
            while j < chars.count, chars[j].isWhitespace { j += 1 }
            let prev = out.last
            let next = j < chars.count ? chars[j] : nil
            if prev == ">" || next == "<" || prev == nil || next == nil {
                // drop inter-tag whitespace
            } else {
                out.append(" ")
            }
            i = j
            continue
        }
        out.append(chars[i])
        if !inPre, matchesTag(chars, at: i, tag: "<pre") { inPre = true }
        if inPre, matchesTag(chars, at: i, tag: "</pre") { inPre = false }
        i += 1
    }
    return out
}

private func matchesTag(_ chars: [Character], at i: Int, tag: String) -> Bool {
    let t = Array(tag)
    guard chars[i] == "<", i + t.count <= chars.count else { return false }
    return Array(chars[i..<(i + t.count)]) == t
}
