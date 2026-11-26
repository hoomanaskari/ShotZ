import AppKit
import ShotzCore
import ShotzUI

/// Drag-out in the action area. A quiet ShotzUI control that starts a file drag of the flattened
/// image instead of a click; the file is rendered when the drag starts.
///
/// Two looks (the action bar uses `DragHandleView.defaultStyle`):
/// - `.thumbnail`: a preview of the result in a ShotzTileButton. It reads as "this is the
///   image: take it" without needing the tooltip; hover shows the tile's ring.
/// - `.icon`: the drag-hand icon in a quiet ShotzButton.
/// Both say "Drag to another app" in the tooltip and show the open-hand cursor.
@MainActor final class DragHandleView: NSView, NSDraggingSource {
    enum Style: String { case thumbnail, icon }
    nonisolated static let defaultStyle: Style = .thumbnail
    static let thumbSize = CGSize(width: 40, height: 22)

    /// Produces the file to drag (rendered at full resolution).
    var makeFile: (() -> URL?)?
    let tile = ShotzTileButton(image: NSImage(size: DragHandleView.thumbSize), size: DragHandleView.thumbSize, label: String(localized: "Drag image"))
    let button = ShotzButton(icon: .dragHandle, role: .quiet, size: EditorControls.actionSize)
    var style: Style = DragHandleView.defaultStyle {
        didSet {
            tile.isHidden = style != .thumbnail
            button.isHidden = style != .icon
            invalidateIntrinsicContentSize()
            superview?.needsLayout = true
        }
    }
    /// The preview of the result shown in the thumbnail style.
    var thumbnail: NSImage? {
        didSet {
            tile.image = thumbnail ?? NSImage(size: Self.thumbSize)
            // The tile takes the image's proportions (22 pt tall, 28–48 pt wide) so nothing is stretched.
            if let size = thumbnail?.size, size.height > 0 {
                let w = min(max((Self.thumbSize.height * size.width / size.height).rounded(), 28), 48)
                tile.tileSize = CGSize(width: w, height: Self.thumbSize.height)
                invalidateIntrinsicContentSize()
                superview?.needsLayout = true
                superview?.superview?.needsLayout = true
            }
        }
    }
    private var shown: ShotzControlView { style == .thumbnail ? tile : button }
    private var mouseDownEvent: NSEvent?
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { updateState() } }
    private var pressing = false { didSet { updateState() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        for v in [tile, button] as [ShotzControlView] {
            v.frame = bounds
            v.autoresizingMask = [.width, .height]
            v.setAccessibilityElement(false)
            addSubview(v)
        }
        tile.isHidden = style != .thumbnail
        button.isHidden = style != .icon
        setShotzToolTip(String(localized: "Drag to another app"))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Drag image"))
        setAccessibilityHelp(String(localized: "Drag the finished image into another app"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { shown.intrinsicContentSize }
    override var isFlipped: Bool { true }

    /// The whole area is the drag source (the control only draws).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    private func updateState() {
        let state = hovering || pressing ? ShotzUI.ControlState(isHovered: hovering, isPressed: pressing) : nil
        tile.stateOverride = state
        button.stateOverride = state
    }

    /// Shows the hover look without a mouse (renders and tests).
    func previewHover(_ on: Bool) { hovering = on }

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

