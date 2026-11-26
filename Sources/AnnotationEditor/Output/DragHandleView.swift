import AppKit

/// Drag-out handle in the toolbar: a chip with a grip and a live thumbnail of the
/// annotated image, so it reads as "pick this up". Drags the flattened file into
/// other apps; the file is rendered when the drag starts.
@MainActor final class DragHandleView: NSView, NSDraggingSource {
    /// Produces the file to drag (rendered at full resolution).
    var makeFile: (() -> URL?)?
    /// Small preview of the current result.
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    private var mouseDownEvent: NSEvent?
    private var hovering = false
    private var tracking: NSTrackingArea?
    static let size = NSSize(width: 64, height: EditorMetrics.toolHeight - 4)

    override init(frame: NSRect) {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: Self.size.width).isActive = true
        heightAnchor.constraint(equalToConstant: Self.size.height).isActive = true
        toolTip = String(localized: "Drag the finished image into another app")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Drag image"))
        setAccessibilityHelp(String(localized: "Drag the finished image into another app"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: r, xRadius: EditorMetrics.corner, yRadius: EditorMetrics.corner)
        (hovering ? NSColor.labelColor.withAlphaComponent(0.08) : NSColor.labelColor.withAlphaComponent(0.035)).setFill()
        path.fill()
        NSColor.separatorColor.setStroke()
        path.lineWidth = 1
        path.stroke()
        // Grip.
        let grip = EditorGlyphs.image(.drag, size: 16)
        let gripRect = NSRect(x: 5, y: r.midY - 8, width: 16, height: 16)
        NSImage(size: grip.size, flipped: false) { rr in
            grip.draw(in: rr)
            NSColor.tertiaryLabelColor.set()
            rr.fill(using: .sourceAtop)
            return true
        }.draw(in: gripRect)
        // Thumbnail of the result.
        let thumbArea = NSRect(x: 23, y: 4, width: r.width - 27, height: r.height - 8)
        if let thumbnail, thumbnail.size.width > 0, thumbnail.size.height > 0 {
            let k = min(thumbArea.width / thumbnail.size.width, thumbArea.height / thumbnail.size.height)
            let size = NSSize(width: thumbnail.size.width * k, height: thumbnail.size.height * k)
            let t = NSRect(x: thumbArea.midX - size.width / 2, y: thumbArea.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSBezierPath(roundedRect: t, xRadius: 2, yRadius: 2).addClip()
            thumbnail.draw(in: t)
            NSGraphicsContext.restoreGraphicsState()
            NSColor.black.withAlphaComponent(0.15).setStroke()
            NSBezierPath(roundedRect: t.insetBy(dx: 0.25, dy: 0.25), xRadius: 2, yRadius: 2).stroke()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true; needsDisplay = true }
    override func mouseExited(with event: NSEvent) { hovering = false; needsDisplay = true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let d = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard d >= 3 else { return }
        mouseDownEvent = nil
        startDrag(with: down, from: self)
    }

    /// Starts a file drag (also used by the title-bar proxy icon).
    func startDrag(with event: NSEvent, from view: NSView) {
        guard let url = makeFile?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(contentsOf: url) ?? NSImage()
        let aspect = preview.size.height > 0 ? preview.size.width / preview.size.height : 1
        let w: CGFloat = 120, h = w / max(aspect, 0.1)
        let p = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), contents: preview)
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
