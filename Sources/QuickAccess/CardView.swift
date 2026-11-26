import AppKit
import ShotzCore

@MainActor protocol CardViewDelegate: AnyObject {
    func card(_ card: CardView, hoverChanged inside: Bool)
    func card(_ card: CardView, perform action: CardAction)
    /// The pasteboard writer for a drag-out, or nil if the file cannot be prepared.
    func cardDragWriter(_ card: CardView) -> NSPasteboardWriting?
    func card(_ card: CardView, isAtSwipeEdge screenPoint: NSPoint) -> Bool
    func card(_ card: CardView, dragEndedWith operation: NSDragOperation, swiped: Bool)
}

/// One thumbnail card (SPEC §4.2). Layer-backed with explicit frames; the
/// controller positions it, the card handles its own mouse and drag-out.
@MainActor final class CardView: NSView, NSDraggingSource {
    let capture: CaptureResult
    weak var delegate: CardViewDelegate?

    /// Set when the card is leaving; it no longer takes events or layout.
    private(set) var isExiting = false
    private(set) var isHovered = false
    private(set) var isDragging = false

    private let style: CardStyle
    private let clip = NSView()
    private let imageLayer = CALayer()
    private let borderLayer = CALayer()
    let overlay: CardOverlayView
    private var thumbnail: CGImage?
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var dragAtEdge = false

    init(capture: CaptureResult, size: CardSize) {
        self.capture = capture
        style = CardStyle(size: size)
        overlay = CardOverlayView(style: style, captionText: Self.caption(for: capture))
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        layer?.shadowColor = .black
        layer?.shadowOffset = CGSize(width: 0, height: -3)
        layer?.shadowRadius = 9

        clip.wantsLayer = true
        clip.layerContentsRedrawPolicy = .never
        clip.layer?.masksToBounds = true
        clip.layer?.cornerRadius = style.cornerRadius
        clip.layer?.cornerCurve = .continuous
        imageLayer.contentsGravity = .resizeAspect
        imageLayer.magnificationFilter = .linear
        imageLayer.minificationFilter = .trilinear
        imageLayer.opacity = 0
        borderLayer.cornerRadius = style.cornerRadius
        borderLayer.cornerCurve = .continuous
        clip.layer?.addSublayer(imageLayer)
        addSubview(clip)
        clip.addSubview(overlay)
        // Border above the overlay's dim so the edge stays crisp.
        clip.layer?.addSublayer(borderLayer)
        borderLayer.zPosition = 10
        overlay.onAction = { [weak self] action in
            guard let self else { return }
            self.delegate?.card(self, perform: action)
        }
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    static func caption(for capture: CaptureResult) -> String {
        "\(Int(capture.pixelSize.width)) × \(Int(capture.pixelSize.height))"
    }

    // MARK: Content

    func setThumbnail(_ image: CGImage, animated: Bool) {
        thumbnail = image
        imageLayer.contents = image
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = imageLayer.presentation()?.opacity ?? 0
        fade.toValue = 1
        fade.duration = animated ? 0.12 : 0
        imageLayer.opacity = 1
        imageLayer.add(fade, forKey: "fade")
    }

    var thumbnailPixelSize: CGSize? { thumbnail.map { CGSize(width: $0.width, height: $0.height) } }

    /// Where the image sits inside the card (aspect-fit).
    var imageRect: CGRect {
        let b = bounds
        let px = capture.pixelSize
        guard px.width > 0, px.height > 0 else { return b }
        let s = min(b.width / px.width, b.height / px.height)
        let w = px.width * s, h = px.height * s
        return CGRect(x: b.midX - w / 2, y: b.midY - h / 2, width: w, height: h)
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.frame = bounds
        overlay.frame = clip.bounds
        imageLayer.frame = clip.bounds
        borderLayer.frame = clip.bounds
        let scale = window?.backingScaleFactor ?? 2
        borderLayer.borderWidth = 1 / scale
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyPalette()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsLayout = true
    }

    private func applyPalette() {
        let palette = CardStyle.palette(for: effectiveAppearance)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        clip.layer?.backgroundColor = palette.backdrop
        borderLayer.borderColor = palette.border
        layer?.shadowOpacity = palette.shadowOpacity
        overlay.apply(palette)
        CATransaction.commit()
    }

    func flash(_ text: String, symbol: String, success: Bool) {
        overlay.showFlash(text, symbol: symbol, success: success)
    }

    func markExiting() {
        isExiting = true
        setHovered(false)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { setHovered(true) }
    override func mouseExited(with event: NSEvent) { setHovered(false) }

    func setHovered(_ hovered: Bool) {
        let effective = hovered && !isExiting && !isDragging
        guard effective != isHovered else { return }
        isHovered = effective
        overlay.setRevealed(effective)
        delegate?.card(self, hoverChanged: effective)
    }

    /// Re-checks hover from the current pointer position (after the card moved under it).
    func refreshHover() {
        guard let window, !isExiting else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(p))
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isExiting else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return overlay.hitTest(convert(local, to: clip)) ?? self
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            mouseDownPoint = nil
            delegate?.card(self, perform: .annotate)
            return
        }
        mouseDownPoint = event.locationInWindow
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start = mouseDownPoint, !isDragging else { return }
        let p = event.locationInWindow
        guard hypot(p.x - start.x, p.y - start.y) >= 3 else { return }
        mouseDownPoint = nil
        beginDrag(with: event)
    }

    override func mouseUp(with event: NSEvent) { mouseDownPoint = nil }

    override func menu(for event: NSEvent) -> NSMenu? {
        let menu = NSMenu()
        let groups: [[CardAction]] = [
            [.copy, .save, .annotate, .quickLook],
            [.showInFinder, .copyFilePath],
            [.close, .closeAndDelete, .closeAll],
        ]
        for (i, group) in groups.enumerated() {
            if i > 0 { menu.addItem(.separator()) }
            for action in group {
                let item = NSMenuItem(title: action.title, action: #selector(menuAction(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = action
                item.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)
                menu.addItem(item)
            }
        }
        return menu
    }

    @objc private func menuAction(_ sender: NSMenuItem) {
        guard let action = sender.representedObject as? CardAction else { return }
        delegate?.card(self, perform: action)
    }

    // MARK: Drag-out

    private func beginDrag(with event: NSEvent) {
        guard let writer = delegate?.cardDragWriter(self) else { return }
        let item = NSDraggingItem(pasteboardWriter: writer)
        item.setDraggingFrame(imageRect, contents: dragImage())
        isDragging = true
        dragAtEdge = false
        setHovered(false)
        let session = beginDraggingSession(with: [item], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = true
        session.draggingFormation = .none
        animator().alphaValue = 0.35
    }

    private func dragImage() -> NSImage {
        let rect = imageRect
        if let thumbnail { return NSImage(cgImage: thumbnail, size: rect.size) }
        return NSImage(size: rect.size, flipped: false) { r in
            NSColor.gray.setFill()
            r.fill()
            return true
        }
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    func ignoreModifierKeys(for session: NSDraggingSession) -> Bool { true }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        let atEdge = delegate?.card(self, isAtSwipeEdge: screenPoint) ?? false
        guard atEdge != dragAtEdge else { return }
        dragAtEdge = atEdge
        // Released at the edge, the card leaves instead of sliding back.
        session.animatesToStartingPositionsOnCancelOrFail = !atEdge
    }

    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        isDragging = false
        let swiped = operation == [] && (delegate?.card(self, isAtSwipeEdge: screenPoint) ?? false)
        if operation == [] && !swiped { animator().alphaValue = 1 }
        delegate?.card(self, dragEndedWith: operation, swiped: swiped)
        if !isExiting { alphaValue = 1; refreshHover() }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .group }
    override func accessibilityLabel() -> String? {
        String(localized: "Screenshot \(capture.displayName), \(Self.caption(for: capture)) pixels")
    }
    override func accessibilityChildren() -> [Any]? { overlay.accessibilityChildren() }
}
