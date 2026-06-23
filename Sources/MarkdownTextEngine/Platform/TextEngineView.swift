// Only platform files import UIKit / AppKit. Core files (Model/, Layout/, Selection/, Render/)
// must never import these frameworks.

#if canImport(UIKit)
import UIKit
import CoreGraphics

/// A UIView that lays out and renders a `TextDocument` using `DocumentRenderer`.
///
/// - Recomputes `DocumentLayout` whenever the view's width changes.
/// - Exposes `intrinsicContentSize` equal to the layout's `contentSize`.
/// - Draws windowed: only the portion covered by the dirty rect is rendered.
/// - Supports basic drag selection via a long-press + pan gesture (Task 3.4).
///   Native loupe / selection handles / edit-menu come in Wave 7.
@MainActor
public final class TextEngineView: UIView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { setNeedsLayout() }
    }

    /// The currently highlighted selection rects (document coordinates).
    /// Set externally or updated by the drag-selection gesture.
    public var currentSelectionRects: [CGRect] = [] {
        didSet { setNeedsDisplay() }
    }

    // MARK: - Internal state (accessible within the module for representable coordination)

    /// The most recently computed layout. Exposed internally so the SwiftUI
    /// representable coordinator can hit-test tapped points against line frames.
    var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)

    // MARK: - Private state

    private var lastLayoutWidth: CGFloat = 0

    /// The current text selection range (used for drag selection).
    private var currentRange: TextRange? = nil

    // MARK: - Initialisation

    public override init(frame: CGRect) {
        super.init(frame: frame)
        setupDragSelection()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupDragSelection()
    }

    // MARK: - Drag selection setup

    private func setupDragSelection() {
        // Long-press begins the selection; panning extends it.
        // We use a LongPressGestureRecognizer + a UIPanGestureRecognizer in parallel.
        let longPress = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleLongPress(_:))
        )
        longPress.minimumPressDuration = 0.4
        addGestureRecognizer(longPress)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        addGestureRecognizer(pan)
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        let pt = gesture.location(in: self)
        let pos = position(at: pt, in: docLayout, doc: document)
        // Start a zero-length range at the tapped position
        currentRange = TextRange(start: pos, end: pos)
        updateSelectionRects()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed || gesture.state == .ended else {
            if gesture.state == .cancelled { clearSelection(); return }
            return
        }
        guard let existingRange = currentRange else { return }
        let pt = gesture.location(in: self)
        let endPos = position(at: pt, in: docLayout, doc: document)
        currentRange = TextRange(start: existingRange.start, end: endPos)
        updateSelectionRects()
    }

    private func clearSelection() {
        currentRange = nil
        currentSelectionRects = []
    }

    private func updateSelectionRects() {
        guard let range = currentRange else {
            currentSelectionRects = []
            return
        }
        currentSelectionRects = selectionRects(for: range, in: docLayout, doc: document)
    }

    // MARK: - Layout

    public override func layoutSubviews() {
        super.layoutSubviews()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        setNeedsDisplay()
    }

    public override var intrinsicContentSize: CGSize {
        docLayout.contentSize
    }

    // MARK: - Drawing

    public override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        DocumentRenderer.draw(docLayout, in: ctx, canvasHeight: bounds.height, visible: rect,
                              selection: currentSelectionRects)
    }
}

#elseif canImport(AppKit)
import AppKit
import CoreGraphics

/// An NSView that lays out and renders a `TextDocument` using `DocumentRenderer`.
///
/// - Recomputes `DocumentLayout` whenever the view's width changes.
/// - Exposes `intrinsicContentSize` equal to the layout's `contentSize`.
/// - Draws windowed: only the portion covered by the dirty rect is rendered.
/// - Supports basic drag selection via mouse events (Task 3.4).
///   Native selection handles / edit-menu come in Wave 7.
/// - Loads images asynchronously via `imageProvider` (Task 6.3): after layout,
///   one `Task` per image source fetches the `CGImage`; on completion, the image
///   is stored in `imageCache` and only the image's reserved rect is invalidated.
@MainActor
public final class TextEngineView: NSView {

    // MARK: - Public state

    /// The document to display.
    public var document: TextDocument = TextDocument(blocks: []) {
        didSet { needsLayout = true }
    }

    /// Optional image provider for async image loading (Task 6.3).
    /// When set, `TextEngineView` requests each image source after layout completes.
    public var imageProvider: (any ImageProvider)? = nil {
        didSet { imageCache = [:]; needsLayout = true }
    }

    /// The currently highlighted selection rects (document coordinates).
    /// Set externally or updated by the drag-selection gesture.
    public var currentSelectionRects: [CGRect] = [] {
        didSet { needsDisplay = true }
    }

    // MARK: - Internal state (accessible within the module for representable coordination)

    /// The most recently computed layout. Exposed internally so the SwiftUI
    /// representable coordinator can hit-test tapped points against line frames.
    var docLayout: DocumentLayout = DocumentLayout(blocks: [], contentSize: .zero)

    // MARK: - Private state

    private var lastLayoutWidth: CGFloat = 0

    /// The anchor position when a drag begins (mouse-down point).
    private var dragAnchor: TextPosition? = nil

    /// Cache of resolved CGImages keyed by source string.
    /// Populated asynchronously by `loadImages()` after each layout.
    private var imageCache: [String: CGImage] = [:]

    /// Set of image sources currently being loaded (to avoid duplicate requests).
    private var loadingImages: Set<String> = []

    // MARK: - Initialisation

    public override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    // MARK: - Mouse / drag selection (AppKit)

    /// Converts an AppKit NSView point (y-up from bottom) to document space (y-down from top).
    private func toDocPoint(_ nsPoint: NSPoint) -> CGPoint {
        CGPoint(x: nsPoint.x, y: bounds.height - nsPoint.y)
    }

    public override func mouseDown(with event: NSEvent) {
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))
        let pos = position(at: pt, in: docLayout, doc: document)
        dragAnchor = pos
        // Zero-length range at anchor — shows caret position
        updateSelectionRects(anchor: pos, active: pos)
    }

    public override func mouseDragged(with event: NSEvent) {
        guard let anchor = dragAnchor else { return }
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))
        let activePos = position(at: pt, in: docLayout, doc: document)
        updateSelectionRects(anchor: anchor, active: activePos)
    }

    public override func mouseUp(with event: NSEvent) {
        guard let anchor = dragAnchor else { return }
        let pt = toDocPoint(convert(event.locationInWindow, from: nil))
        let activePos = position(at: pt, in: docLayout, doc: document)
        updateSelectionRects(anchor: anchor, active: activePos)
        // If released at same position as anchor, clear selection
        if anchor == activePos {
            currentSelectionRects = []
            dragAnchor = nil
        }
    }

    private func updateSelectionRects(anchor: TextPosition, active: TextPosition) {
        let range = TextRange(start: anchor, end: active)
        currentSelectionRects = selectionRects(for: range, in: docLayout, doc: document)
    }

    // Accept mouse events
    public override var acceptsFirstResponder: Bool { true }

    // MARK: - Layout

    public override func layout() {
        super.layout()
        let w = bounds.width
        guard w > 0, w != lastLayoutWidth else { return }
        lastLayoutWidth = w
        docLayout = LayoutEngine.layout(document, width: w)
        invalidateIntrinsicContentSize()
        needsDisplay = true
        // After (re)layout, kick off async image loading for any sources in the new layout.
        if #available(macOS 10.15, *) { loadImages() }
    }

    public override var intrinsicContentSize: NSSize {
        docLayout.contentSize
    }

    // MARK: - Async image loading (Task 6.3)

    /// Iterates all `.image` blocks in the current layout and fires async Tasks
    /// to fetch each uncached source via `imageProvider`.
    ///
    /// On completion, the CGImage is stored in `imageCache` and only the image's
    /// reserved rect is invalidated for a partial redraw.
    @available(macOS 10.15, *)
    private func loadImages() {
        guard let provider = imageProvider else { return }
        for block in docLayout.blocks {
            guard case .image(let rect, let attachment) = block else { continue }
            let source = attachment.source
            guard imageCache[source] == nil, !loadingImages.contains(source) else { continue }
            loadingImages.insert(source)
            Task { [weak self] in
                guard let self else { return }
                let cgImage = await provider.image(for: source)
                // Back on MainActor (Task inherits actor from @MainActor type).
                self.loadingImages.remove(source)
                if let cgImage {
                    self.imageCache[source] = cgImage
                    // Partial redraw: invalidate only the image's rect.
                    self.setNeedsDisplay(rect)
                }
                // If nil: leave placeholder (do not mark as loading again).
            }
        }
    }

    // MARK: - Drawing

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        // On AppKit, NSView draws with y-up (bottom-left origin) by default.
        // DocumentRenderer's draw() applies the y-flip internally using
        // canvasHeight (the full bounds height), not the dirty rect height.
        // We pass dirtyRect as `visible` so the renderer culls off-screen
        // blocks correctly.
        let visibleRect = CGRect(origin: dirtyRect.origin,
                                 size: CGSize(width: dirtyRect.width, height: dirtyRect.height))
        DocumentRenderer.draw(
            docLayout,
            in: ctx,
            canvasHeight: bounds.height,
            visible: visibleRect,
            selection: currentSelectionRects,
            images: imageCache
        )
    }
}
#endif
