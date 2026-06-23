import CoreText
import CoreGraphics

// MARK: - Font helper (Wave 0)

func ctFont(for style: TextStyle) -> CTFont {
    var traits: CTFontSymbolicTraits = []
    if style.isBold { traits.insert(.traitBold) }
    if style.isItalic { traits.insert(.traitItalic) }
    if style.isMonospace { traits.insert(.traitMonoSpace) }
    let base = style.isMonospace
        ? CTFontCreateWithName("Menlo" as CFString, style.fontSize, nil)
        : CTFontCreateUIFontForLanguage(.system, style.fontSize, nil)!
    return CTFontCreateCopyWithSymbolicTraits(base, style.fontSize, nil, traits, traits) ?? base
}

// MARK: - Attributed string builder

/// Converts `InlineRun` tree into a `CFMutableAttributedString`.
/// Returns the string and a parallel array of (range, style) for each text segment.
func buildAttributedString(from runs: [InlineRun]) -> CFMutableAttributedString {
    let attrStr = CFAttributedStringCreateMutable(nil, 0)!
    appendRuns(runs, into: attrStr)
    return attrStr
}

private func appendRuns(_ runs: [InlineRun], into attrStr: CFMutableAttributedString) {
    for run in runs {
        switch run {
        case .text(let string, let style):
            let font = ctFont(for: style)
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: font,
                kCTForegroundColorAttributeName: style.color
            ]
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), string as CFString)
            let newLen = CFAttributedStringGetLength(attrStr)
            CFAttributedStringSetAttributes(attrStr, CFRangeMake(len, newLen - len),
                                            attrs as CFDictionary, false)

        case .link(let innerRuns, _):
            appendRuns(innerRuns, into: attrStr)

        case .inlineImage:
            // Placeholder: images not rendered in this wave
            break

        case .lineBreak(let hard):
            let breakChar = hard ? "\n" : "\u{2028}" // LINE SEPARATOR for soft break
            let len = CFAttributedStringGetLength(attrStr)
            CFAttributedStringReplaceString(attrStr, CFRangeMake(len, 0), breakChar as CFString)
        }
    }
}

// MARK: - Paragraph layout

/// Lays out a single `Paragraph` into a `BlockFrame.text`, starting at `origin`.
/// Returns the frame and advances `origin.y` past the block (including spacingAfter).
public func layoutParagraph(_ p: Paragraph, width: CGFloat, origin: CGPoint) -> BlockFrame {
    let attrStr = buildAttributedString(from: p.runs)
    let totalChars = CFAttributedStringGetLength(attrStr)
    let typesetter = CTTypesetterCreateWithAttributedString(attrStr)

    let style = p.style
    let lineSpacing = style.lineSpacing
    let leadingIndent = style.leadingIndent
    let lineWidth = width - leadingIndent

    var lineFrames: [LineFrame] = []
    var charIndex = 0
    var cursorY = origin.y  // current top of the line

    while charIndex < totalChars {
        // How many characters fit on this line?
        let count = CTTypesetterSuggestLineBreak(typesetter, charIndex, Double(lineWidth))
        if count == 0 { break } // safety: avoid infinite loop

        let ctLine = CTTypesetterCreateLine(typesetter, CFRangeMake(charIndex, count))

        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        var leading: CGFloat = 0
        let lineWidth_ = CGFloat(CTLineGetTypographicBounds(ctLine, &ascent, &descent, &leading))

        // Baseline is at cursorY + ascent
        let lineOrigin = CGPoint(x: origin.x + leadingIndent, y: cursorY)
        let lineSize = CGSize(width: lineWidth_, height: ascent + descent)

        lineFrames.append(LineFrame(
            origin: lineOrigin,
            size: lineSize,
            ascent: ascent,
            descent: descent,
            ctLine: ctLine,
            charRange: charIndex..<(charIndex + count)
        ))

        cursorY += ascent + descent + lineSpacing
        charIndex += count
    }

    let blockHeight = cursorY - origin.y
    let blockRect = CGRect(x: origin.x, y: origin.y, width: width, height: blockHeight)
    return .text(rect: blockRect, lines: lineFrames)
}

// MARK: - LayoutEngine

public enum LayoutEngine {
    public static func layout(_ doc: TextDocument, width: CGFloat) -> DocumentLayout {
        var blockFrames: [BlockFrame] = []
        var cursorY: CGFloat = 0

        for block in doc.blocks {
            switch block {
            case .paragraph(let p):
                cursorY += p.style.spacingBefore
                let origin = CGPoint(x: 0, y: cursorY)
                let frame = layoutParagraph(p, width: width, origin: origin)
                blockFrames.append(frame)
                if case .text(let rect, _) = frame {
                    cursorY = rect.maxY
                }
                cursorY += p.style.spacingAfter

            case .thematicBreak(let rule):
                let ruleHeight = rule.thickness
                let rect = CGRect(x: 0, y: cursorY, width: width, height: ruleHeight)
                blockFrames.append(.rule(rect))
                cursorY += ruleHeight

            case .image(let attachment):
                let imgSize = attachment.intrinsicSize
                let rect = CGRect(x: 0, y: cursorY, width: imgSize.width, height: imgSize.height)
                blockFrames.append(.image(rect: rect, attachment: attachment))
                cursorY += imgSize.height

            case .codeBlock:
                // Placeholder – code blocks handled in a later wave
                let rect = CGRect(x: 0, y: cursorY, width: width, height: 0)
                blockFrames.append(.code(rect: rect))

            case .list:
                // Placeholder – lists handled in a later wave
                let rect = CGRect(x: 0, y: cursorY, width: width, height: 0)
                blockFrames.append(.list(rect: rect, items: []))

            case .quote:
                // Placeholder – block quotes handled in a later wave
                let rect = CGRect(x: 0, y: cursorY, width: width, height: 0)
                blockFrames.append(.quote(rect: rect, inner: []))

            case .table:
                // Placeholder – tables handled in a later wave
                let rect = CGRect(x: 0, y: cursorY, width: width, height: 0)
                blockFrames.append(.table(rect: rect))
            }
        }

        return DocumentLayout(
            blocks: blockFrames,
            contentSize: CGSize(width: width, height: cursorY)
        )
    }
}
