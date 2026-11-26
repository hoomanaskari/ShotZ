import AppKit
import ShotzCore

@MainActor protocol CardViewDelegate: AnyObject {
    func card(_ card: CardView, hoverChanged inside: Bool)
    func card(_ card: CardView, perform action: CardAction)
    /// The pasteboard writer for a drag-out, or nil if the file cannot be prepared.
    /// A real mouse-moved event inside the card (never sent for a card that
    /// merely appears or moves under a resting pointer).
    func cardPointerMoved(_ card: CardView, buttonsDown: Bool)
    func cardDragWriter(_ card: CardView) -> NSPasteboardWriting?
    func card(_ card: CardView, isAtSwipeEdge screenPoint: NSPoint) -> Bool
    func card(_ card: CardView, dragEndedWith operation: NSDragOperation, swiped: Bool)
}

/// One thumbnail card (SPEC §4.2). Layer-backed with explicit frames; the
/// controller positions it, the card handles its own mouse and drag-out.
@MainActor final class CardView: NSView, NSDraggingSource {
    let source: CardSource
    var capture: CaptureResult { source.capture }
    weak var delegate: CardViewDelegate?

    /// Set when the card is leaving; it no longer takes events or layout.
    private(set) var isExiting = false
    private(set) var isHovered = false
    private(set) var isDragging = false

    private let style: CardStyle
    private let clip = NSView()
    private let imageLayer = CALayer()
    /// Blurred aspect-fill of the thumbnail behind letterboxed images.
    private let backdropLayer = CALayer()
    private let backdropTint = CALayer()
    private let contactShadow = CALayer()
    private let borderLayer = CALayer()
    /// Built on first use (hover, confirmation, VoiceOver): its glass
    /// controls are the costliest part of a card, and most cards are never hovered.
    private var overlayStorage: CardOverlayView?
    var overlay: CardOverlayView {
        if let overlayStorage { return overlayStorage }
        let o = CardOverlayView(style: style, captionText: source.caption)
        o.onAction = { [weak self] action in
            guard let self else { return }
            self.delegate?.card(self, perform: action)
        }
        o.frame = clip.bounds
        clip.addSubview(o)
        o.apply(CardStyle.palette(for: effectiveAppearance))
        o.layoutSubtreeIfNeeded()
        overlayStorage = o
        return o
    }
    private var thumbnail: CGImage?
    private var trackingArea: NSTrackingArea?
    private var mouseDownPoint: NSPoint?
    private var dragAtEdge = false

    init(source: CardSource, size: CardSize) {
        self.source = source
        style = CardStyle(size: size)
        super.init(frame: CGRect(origin: .zero, size: CGSize(width: size.width, height: size.height)))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.masksToBounds = false
        // Two shadows: a large soft ambient one on the card layer, and a tight
        // contact shadow that keeps the edge defined on any background.
        layer?.shadowColor = .black
        layer?.shadowOffset = CGSize(width: 0, height: -4)
        layer?.shadowRadius = 12
        contactShadow.shadowColor = .black
        contactShadow.shadowOffset = CGSize(width: 0, height: -0.5)
        contactShadow.shadowRadius = 1.5
        layer?.addSublayer(contactShadow)

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
        backdropLayer.contentsGravity = .resizeAspectFill
        backdropLayer.opacity = 0
        backdropTint.opacity = 0
        clip.layer?.addSublayer(backdropLayer)
        clip.layer?.addSublayer(backdropTint)
        clip.layer?.addSublayer(imageLayer)
        addSubview(clip)
        // Border above the overlay's scrim so the edge stays crisp.
        clip.layer?.addSublayer(borderLayer)
        borderLayer.zPosition = 10
        applyPalette()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

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

    var thumbnailImage: CGImage? { thumbnail }
    var thumbnailPixelSize: CGSize? { thumbnail.map { CGSize(width: $0.width, height: $0.height) } }

    func setBackdrop(_ image: CGImage) {
        backdropLayer.contents = image
        for layer in [backdropLayer, backdropTint] {
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.18
            layer.opacity = 1
            layer.add(fade, forKey: "fade")
        }
    }

    var hasBackdrop: Bool { backdropLayer.contents != nil }

    /// Where the image sits inside the card (aspect-fit).
    var imageRect: CGRect {
        let b = bounds
        let px = source.pixelSize
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
        overlayStorage?.frame = clip.bounds
        imageLayer.frame = clip.bounds
        backdropLayer.frame = clip.bounds
        backdropTint.frame = clip.bounds
        borderLayer.frame = clip.bounds
        let scale = window?.backingScaleFactor ?? 2
        borderLayer.borderWidth = 1 / scale
        let path = CGPath(roundedRect: bounds, cornerWidth: style.cornerRadius, cornerHeight: style.cornerRadius, transform: nil)
        layer?.shadowPath = path
        contactShadow.frame = bounds
        contactShadow.shadowPath = path
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
        backdropTint.backgroundColor = palette.backdropTint
        borderLayer.borderColor = palette.border
        layer?.shadowOpacity = palette.ambientShadowOpacity
        contactShadow.shadowOpacity = palette.contactShadowOpacity
        overlayStorage?.apply(palette)
        CATransaction.commit()
    }

    func flash(_ text: String, success: Bool) {
        overlay.showFlash(text, success: success)
    }

    func markExiting() {
        isExiting = true
        setHovered(false)
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    /// Set by the self-test so the real pointer can't interfere with simulated hover.
    static var ignoresRealPointer = false

    override func mouseEntered(with event: NSEvent) { if !Self.ignoresRealPointer { setHovered(true) } }
    override func mouseExited(with event: NSEvent) { if !Self.ignoresRealPointer { setHovered(false) } }

    override func mouseMoved(with event: NSEvent) {
        guard !Self.ignoresRealPointer, !isExiting else { return }
        if !isHovered { setHovered(true) }
        delegate?.cardPointerMoved(self, buttonsDown: NSEvent.pressedMouseButtons != 0)
    }

    func setHovered(_ hovered: Bool) {
        let effective = hovered && !isExiting && !isDragging
        guard effective != isHovered else { return }
        isHovered = effective
        if effective || overlayStorage != nil { overlay.setRevealed(effective) }
        delegate?.card(self, hoverChanged: effective)
    }

    /// Re-checks hover from the current pointer position (after the card moved under it).
    func refreshHover() {
        guard let window, !isExiting, !Self.ignoresRealPointer else { return }
        let p = convert(window.mouseLocationOutsideOfEventStream, from: nil)
        setHovered(bounds.contains(p))
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isExiting else { return nil }
        let local = convert(point, from: superview)
        guard bounds.contains(local) else { return nil }
        return overlayStorage?.hitTest(convert(local, to: clip)) ?? self
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
                item.image = CardIcon.action(action).image(pointSize: 13)
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
        source.isAnnotated
            ? String(localized: "Annotated screenshot \(capture.displayName), \(source.caption) pixels")
            : String(localized: "Screenshot \(capture.displayName), \(source.caption) pixels")
    }
    override func accessibilityChildren() -> [Any]? { overlay.accessibilityChildren() }
}
