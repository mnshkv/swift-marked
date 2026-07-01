import CoreGraphics

/// A declarative rule for recognising a custom inline token (hashtag, mention,
/// emoji shortcode, …) inside plain text and rendering it specially.
public struct InlineRule: Sendable {
    /// Routing identifier returned to the host on tap, e.g. "hashtag".
    public let id: String
    /// The character that opens the token, e.g. "#", "@", ":".
    public var trigger: Character
    /// The set of characters allowed in the token body.
    public var body: BodyClass
    /// Optional closing delimiter (e.g. ":" for `:smile:`). When nil, the body
    /// is scanned until the first character not in `body`.
    public var closing: Character?
    /// Minimum number of body characters required for a match (default 1).
    public var minBodyLength: Int
    /// When true (default), the trigger must start the text or be preceded by a
    /// non-word character (so `email@host` does not match an `@` rule).
    public var requiresLeadingBoundary: Bool
    /// How a matched token is rendered.
    public var output: Output
    /// When true (default), the rendered span is tappable and dispatches a
    /// `CustomInlineTap` to the host.
    public var isTappable: Bool

    public init(
        id: String,
        trigger: Character,
        body: BodyClass = .word,
        closing: Character? = nil,
        minBodyLength: Int = 1,
        requiresLeadingBoundary: Bool = true,
        output: Output,
        isTappable: Bool = true
    ) {
        self.id = id
        self.trigger = trigger
        self.body = body
        self.closing = closing
        self.minBodyLength = minBodyLength
        self.requiresLeadingBoundary = requiresLeadingBoundary
        self.output = output
        self.isTappable = isTappable
    }

    /// The characters permitted in a token body.
    public enum BodyClass: Sendable {
        /// Letters, digits and underscore.
        case word
        /// An explicit set of allowed characters.
        case custom(Set<Character>)

        func contains(_ c: Character) -> Bool {
            switch self {
            case .word: return c.isLetter || c.isNumber || c == "_"
            case .custom(let set): return set.contains(c)
            }
        }
    }

    /// How a matched token renders.
    public enum Output: Sendable {
        /// Render as styled text (colour, bold, italic, optional pill background).
        case styledText(InlineDecoration)
        /// Render as an inline image whose source key is `keyPrefix + body`,
        /// resolved by the host's `ImageProvider`.
        case image(keyPrefix: String)
    }
}

/// Visual decoration applied to a `.styledText` rule match.
public struct InlineDecoration: Sendable {
    /// Foreground colour; nil inherits the surrounding text colour.
    public var color: CGColor?
    public var isBold: Bool
    public var isItalic: Bool
    /// Rounded background "pill" colour; nil draws no background.
    public var background: CGColor?
    /// Whether the trigger character is part of the displayed text
    /// (true for `#tag`/`@user`, false for `:emoji:` shortcodes).
    public var includeTrigger: Bool

    public init(
        color: CGColor? = nil,
        isBold: Bool = false,
        isItalic: Bool = false,
        background: CGColor? = nil,
        includeTrigger: Bool = true
    ) {
        self.color = color
        self.isBold = isBold
        self.isItalic = isItalic
        self.background = background
        self.includeTrigger = includeTrigger
    }
}

/// Delivered to `MarkdownView`'s `onCustomTap` when a custom rule span is tapped.
public struct CustomInlineTap: Sendable, Equatable {
    /// The `InlineRule.id` of the rule that produced the span.
    public var ruleID: String
    /// The matched body text, without trigger/closing delimiters (e.g. "swift").
    public var value: String

    public init(ruleID: String, value: String) {
        self.ruleID = ruleID
        self.value = value
    }
}
