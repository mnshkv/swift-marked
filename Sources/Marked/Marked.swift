@_exported import MarkdownAST
@_exported import MarkdownTextEngine

/// Appearance for rendering. The core stays SwiftUI-free; the SwiftUI view maps
/// `ColorScheme` → `MarkdownColorScheme`.
public enum MarkdownColorScheme: Sendable { case light, dark }
