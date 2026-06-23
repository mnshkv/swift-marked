import CoreGraphics

// MARK: - Private helpers

private func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> CGColor {
    CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}

// MARK: - MarkdownStyle

/// Full styling configuration for the Markdown renderer.
public struct MarkdownStyle: Sendable {

    // MARK: Nested types

    /// Semantic color palette for one color scheme (light or dark).
    public struct Palette: Sendable {
        public var text: CGColor
        public var secondary: CGColor
        public var link: CGColor
        public var code: CGColor
        public var rule: CGColor

        public init(
            text: CGColor,
            secondary: CGColor,
            link: CGColor,
            code: CGColor,
            rule: CGColor
        ) {
            self.text = text
            self.secondary = secondary
            self.link = link
            self.code = code
            self.rule = rule
        }
    }

    /// Spacing constants used across block elements.
    public struct Spacing: Sendable {
        public var paragraphAfter: CGFloat
        public var headingBefore: CGFloat
        public var headingAfter: CGFloat
        public var definitionIndent: CGFloat

        public init(
            paragraphAfter: CGFloat,
            headingBefore: CGFloat,
            headingAfter: CGFloat,
            definitionIndent: CGFloat
        ) {
            self.paragraphAfter = paragraphAfter
            self.headingBefore = headingBefore
            self.headingAfter = headingAfter
            self.definitionIndent = definitionIndent
        }
    }

    // MARK: Fields

    public var baseFontSize: CGFloat
    public var headingSizes: [CGFloat]     // 6 elements: h1..h6
    public var codeFontSize: CGFloat
    public var footnoteFontSize: CGFloat
    public var inlineImageSize: CGSize
    public var blockImage: CGSize
    public var light: Palette
    public var dark: Palette
    public var spacing: Spacing

    // MARK: Memberwise init

    public init(
        baseFontSize: CGFloat,
        headingSizes: [CGFloat],
        codeFontSize: CGFloat,
        footnoteFontSize: CGFloat,
        inlineImageSize: CGSize,
        blockImage: CGSize,
        light: Palette,
        dark: Palette,
        spacing: Spacing
    ) {
        self.baseFontSize = baseFontSize
        self.headingSizes = headingSizes
        self.codeFontSize = codeFontSize
        self.footnoteFontSize = footnoteFontSize
        self.inlineImageSize = inlineImageSize
        self.blockImage = blockImage
        self.light = light
        self.dark = dark
        self.spacing = spacing
    }

    // MARK: Default

    public static let `default` = MarkdownStyle(
        baseFontSize: 17,
        headingSizes: [28, 23, 19, 17, 15, 14],
        codeFontSize: 14,
        footnoteFontSize: 13,
        inlineImageSize: CGSize(width: 18, height: 18),
        blockImage: CGSize(width: 320, height: 180),
        light: Palette(
            text:      rgb(0x1E, 0x1E, 0x20),
            secondary: rgb(0x6E, 0x6E, 0x78),
            link:      rgb(0x0A, 0x6C, 0xF5),
            code:      rgb(0x5A, 0x5A, 0x66),
            rule:      rgb(0xCC, 0xCC, 0xD2)
        ),
        dark: Palette(
            text:      rgb(0xEC, 0xEC, 0xEE),
            secondary: rgb(0x9A, 0x9A, 0xA2),
            link:      rgb(0x4D, 0x9B, 0xFF),
            code:      rgb(0xB0, 0xB0, 0xBC),
            rule:      rgb(0x3A, 0x3A, 0x40)
        ),
        spacing: Spacing(
            paragraphAfter: 10,
            headingBefore: 14,
            headingAfter: 6,
            definitionIndent: 16
        )
    )
}
