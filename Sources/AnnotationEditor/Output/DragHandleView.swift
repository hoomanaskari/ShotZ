import AppKit
import ShotzCore
import ShotzUI

/// Drag-out in the action area: a quiet ShotzUI icon button (drag handle) that starts a file
/// drag of the flattened image instead of a click. The file is rendered when the drag starts.
/// Hover and press are shown through the button's own ShotzUI states.
@MainActor final class DragHandleView: NSView, NSDraggingSource {
    /// Produces the file to drag (rendered at full resolution).
    var makeFile: (() -> URL?)?
    let button = ShotzButton(icon: .dragHandle, role: .quiet, size: EditorControls.size)
    private var mouseDownEvent: NSEvent?
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { updateState() } }
    private var pressing = false { didSet { updateState() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        button.frame = bounds
        button.autoresizingMask = [.width, .height]
        addSubview(button)
        setShotzToolTip(String(localized: "Drag the image into another app"))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Drag image"))
        setAccessibilityHelp(String(localized: "Drag the finished image into another app"))
        button.setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { button.intrinsicContentSize }
    override var isFlipped: Bool { true }

    /// The whole area is the drag source (the button only draws).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    private func updateState() {
        button.stateOverride = hovering || pressing ? ShotzUI.ControlState(isHovered: hovering, isPressed: pressing) : nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) {
        mouseDownEvent = event
        pressing = true
    }

    override func mouseUp(with event: NSEvent) {
        pressing = false
        mouseDownEvent = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let d = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard d >= 3 else { return }
        mouseDownEvent = nil
        pressing = false
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
