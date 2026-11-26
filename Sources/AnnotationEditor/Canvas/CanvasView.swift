import AnnotationKit
import AppKit

/// Keys the canvas does not handle itself (tool shortcuts, nudges, delete…).
@MainActor protocol CanvasKeyHandling: AnyObject {
    func canvasKeyDown(_ event: NSEvent) -> Bool
}

/// The magnified document view. Coordinates are canvas units (one base-image
/// pixel each, top-left origin). Layer tree (ARCHITECTURE §6):
/// background fill → image shadow → clip (crop, corner radius) → world
/// (base image, redactions, objects). Nothing here re-rasterises the base image.
@MainActor final class CanvasView: NSView {
    let model: EditorModel
    let layers: ObjectLayerStore
    weak var keyHandler: CanvasKeyHandling?
    /// Called after the extent or image placement changed.
    var onLayoutChange: (() -> Void)?
    private(set) lazy var text = TextEditSession(canvas: self)

    private let root = CALayer()
    private let backgroundLayer = CAGradientLayer()
    private let shadowLayer = CALayer()
    private let clipLayer = CALayer()
    private(set) var canvasLayout: CanvasLayout
    /// Opaque content bounds of window captures (transparent margins), for auto-balance.
    let opaqueBounds: CGRect?
    private var spaceHeld = false
    private var panStart: (window: NSPoint, origin: NSPoint)?
    private var trackingArea: NSTrackingArea?

    init(model: EditorModel, base: BaseImageProvider, image: CGImage) {
        self.model = model
        layers = ObjectLayerStore(base: base)
        opaqueBounds = OpaqueBounds.compute(image)
        canvasLayout = CanvasLayout.make(document: model.document, editingCrop: false, opaqueBounds: opaqueBounds)
        super.init(frame: NSRect(origin: .zero, size: canvasLayout.extent))
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        guard let layer else { return }
        for l in [root, backgroundLayer, shadowLayer, clipLayer] {
            l.actions = ObjectLayerStore.noActions.merging(["colors": NSNull(), "startPoint": NSNull(), "endPoint": NSNull(),
                                                             "cornerRadius": NSNull(), "shadowPath": NSNull(),
                                                             "shadowOpacity": NSNull(), "backgroundColor": NSNull()]) { a, _ in a }
            l.anchorPoint = .zero
        }
        layer.addSublayer(root)
        root.addSublayer(backgroundLayer)
        root.addSublayer(shadowLayer)
        root.addSublayer(clipLayer)
        clipLayer.masksToBounds = true
        clipLayer.addSublayer(layers.world)
        layers.setBaseImage(image, pixelSize: model.document.pixelSize)
        layers.sync(model.document)
        relayout()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var isOpaque: Bool { false }

    // MARK: Layout

    /// Recomputes the extent, crop clip and background after document or tool changes.
    func relayout() {
        let newLayout = CanvasLayout.make(
            document: model.document, editingCrop: model.toolKind == .crop, opaqueBounds: opaqueBounds
        )
        let changed = newLayout != canvasLayout
        canvasLayout = newLayout
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if frame.size != canvasLayout.extent { setFrameSize(canvasLayout.extent) }
        layoutRoot()
        clipLayer.frame = canvasLayout.imageFrame
        layers.world.frame = CGRect(
            x: canvasLayout.offset.dx - canvasLayout.imageFrame.minX, y: canvasLayout.offset.dy - canvasLayout.imageFrame.minY,
            width: model.document.pixelSize.width, height: model.document.pixelSize.height
        )
        applyBackground()
        CATransaction.commit()
        if changed { onLayoutChange?() }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutRoot()
        CATransaction.commit()
    }

    /// The root container uses a top-left origin whatever AppKit chose for the backing layer.
    private func layoutRoot() {
        guard let layer else { return }
        root.frame = layer.bounds
        let backingIsTopLeft = convertToLayer(NSPoint(x: 0, y: 0)).y < 1
        root.isGeometryFlipped = !backingIsTopLeft
    }

    private func applyBackground() {
        guard let bg = canvasLayout.background else {
            backgroundLayer.isHidden = true
            shadowLayer.isHidden = true
            clipLayer.cornerRadius = 0
            return
        }
        backgroundLayer.isHidden = false
        backgroundLayer.frame = CGRect(origin: .zero, size: canvasLayout.extent)
        switch bg.fill {
        case .none:
            backgroundLayer.colors = nil
            backgroundLayer.backgroundColor = nil
        case .solid(let c):
            backgroundLayer.colors = nil
            backgroundLayer.backgroundColor = c.cgColor
        case .gradient(let g):
            backgroundLayer.backgroundColor = nil
            backgroundLayer.colors = [g.from.cgColor, g.to.cgColor]
            let (s, e) = GradientGeometry.points(angle: g.angle)
            backgroundLayer.startPoint = s
            backgroundLayer.endPoint = e
        }
        // Window captures carry their own transparent shadow: no extra shadow or rounding.
        let isWindow = opaqueBounds != nil
        let radius = isWindow ? 0 : min(bg.cornerRadius, min(canvasLayout.imageFrame.width, canvasLayout.imageFrame.height) / 2)
        clipLayer.cornerRadius = radius
        shadowLayer.isHidden = isWindow || bg.shadow == .off
        shadowLayer.frame = canvasLayout.imageFrame
        shadowLayer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: canvasLayout.imageFrame.size),
                                        cornerWidth: radius, cornerHeight: radius, transform: nil)
        let long = max(canvasLayout.imageFrame.width, canvasLayout.imageFrame.height)
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = bg.shadow == .strong ? 0.45 : 0.25
        shadowLayer.shadowRadius = long * (bg.shadow == .strong ? 0.025 : 0.015)
        // The root is top-left; a positive y offset casts the shadow downwards.
        shadowLayer.shadowOffset = CGSize(width: 0, height: (root.isGeometryFlipped ? 1 : -1) * long * 0.008)
    }

    // MARK: Coordinates

    func imagePoint(for event: NSEvent) -> CGPoint {
        canvasLayout.toImage(convert(event.locationInWindow, from: nil))
    }

    func toolEvent(_ event: NSEvent) -> ToolEvent {
        var m: ToolModifiers = []
        if event.modifierFlags.contains(.shift) { m.insert(.shift) }
        if event.modifierFlags.contains(.option) { m.insert(.option) }
        if event.modifierFlags.contains(.command) { m.insert(.command) }
        return ToolEvent(imagePoint(for: event), m, clickCount: event.clickCount)
    }

    // MARK: Mouse

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if spaceHeld, let clip = enclosingScrollView?.contentView {
            panStart = (event.locationInWindow, clip.bounds.origin)
            NSCursor.closedHand.set()
            return
        }
        if text.isEditingText {
            text.endEditing()
            if model.toolKind == .select || model.toolKind == .text { return }
        }
        model.tool.mouseDown(toolEvent(event))
    }

    override func mouseDragged(with event: NSEvent) {
        if let pan = panStart, let scroll = enclosingScrollView {
            let m = scroll.magnification
            let d = NSPoint(x: event.locationInWindow.x - pan.window.x, y: event.locationInWindow.y - pan.window.y)
            scroll.contentView.scroll(to: NSPoint(x: pan.origin.x - d.x / m, y: pan.origin.y + d.y / m))
            scroll.reflectScrolledClipView(scroll.contentView)
            return
        }
        autoscroll(with: event)
        model.tool.mouseDragged(toolEvent(event))
    }

    override func mouseUp(with event: NSEvent) {
        if panStart != nil {
            panStart = nil
            (spaceHeld ? NSCursor.openHand : NSCursor.arrow).set()
            return
        }
        model.tool.mouseUp(toolEvent(event))
        updateCursor(event)
    }

    override func mouseMoved(with event: NSEvent) { updateCursor(event) }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect, .cursorUpdate],
                                  owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func cursorUpdate(with event: NSEvent) { updateCursor(event) }

    func updateCursor(_ event: NSEvent? = nil) {
        if spaceHeld { (panStart == nil ? NSCursor.openHand : NSCursor.closedHand).set(); return }
        guard let window else { return }
        let location = event?.locationInWindow ?? window.mouseLocationOutsideOfEventStream
        let p = canvasLayout.toImage(convert(location, from: nil))
        var m: ToolModifiers = []
        if NSEvent.modifierFlags.contains(.shift) { m.insert(.shift) }
        CursorMapping.cursor(for: model.tool.cursor(at: p, modifiers: m)).set()
    }

    // MARK: Keys

    override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " ", event.modifierFlags.intersection([.command, .control, .option]).isEmpty {
            if !spaceHeld { spaceHeld = true; updateCursor() }
            return
        }
        if keyHandler?.canvasKeyDown(event) == true { return }
        super.keyDown(with: event)
    }

    override func keyUp(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " {
            spaceHeld = false
            updateCursor()
            return
        }
        super.keyUp(with: event)
    }

    override func resignFirstResponder() -> Bool {
        spaceHeld = false
        return super.resignFirstResponder()
    }
}
