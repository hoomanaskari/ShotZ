import AppKit
import ShotzCore
import ShotzUI

/// Drag-out in the action area. A quiet ShotzUI control that starts a file drag of the flattened
/// image instead of a click; the file is rendered when the drag starts.
///
/// Two looks (the action bar uses `DragHandleView.defaultStyle`):
/// - `.thumbnail`: a small preview of the result next to a grip, in a quiet chip. It reads as
///   "this is the image: take it" without needing the tooltip.
/// - `.icon`: the drag-hand icon alone; on hover a grip appears beside it.
/// Both say "Drag to another app" in the tooltip and show the open-hand cursor.
@MainActor final class DragHandleView: NSView, NSDraggingSource {
    enum Style: String { case thumbnail, icon }
    nonisolated static let defaultStyle: Style = .thumbnail

    /// Produces the file to drag (rendered at full resolution).
    var makeFile: (() -> URL?)?
    let chip = DragChip(size: EditorControls.actionSize)
    var style: Style {
        get { chip.style }
        set { chip.style = newValue; invalidateIntrinsicContentSize() }
    }
    /// The preview of the result shown in the thumbnail style.
    var thumbnail: NSImage? {
        get { chip.thumbnail }
        set { chip.thumbnail = newValue }
    }
    private var mouseDownEvent: NSEvent?
    private var tracking: NSTrackingArea?
    private var hovering = false { didSet { updateState() } }
    private var pressing = false { didSet { updateState() } }

    override init(frame: NSRect) {
        super.init(frame: frame)
        chip.frame = bounds
        chip.autoresizingMask = [.width, .height]
        addSubview(chip)
        setShotzToolTip(String(localized: "Drag to another app"))
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Drag image"))
        setAccessibilityHelp(String(localized: "Drag the finished image into another app"))
        chip.setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { chip.intrinsicContentSize }
    override var isFlipped: Bool { true }

    /// The whole area is the drag source (the chip only draws).
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    private func updateState() {
        chip.stateOverride = hovering || pressing ? ShotzUI.ControlState(isHovered: hovering, isPressed: pressing) : nil
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

/// The drag-out control's look, drawn with ShotzUI's quiet chrome, icon and palette.
@MainActor final class DragChip: ShotzControlView {
    var style: DragHandleView.Style = DragHandleView.defaultStyle { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    var thumbnail: NSImage? { didSet { needsDisplay = true } }
    let role: ShotzUI.ControlRole = .quiet

    static let thumbSize = CGSize(width: 36, height: 20)
    private static let gripWidth: CGFloat = 6

    init(size: ShotzUI.ControlSize) {
        super.init(frame: .zero)
        shotzSize = size
    }

    override var intrinsicContentSize: NSSize {
        let s = shotzSize
        switch style {
        case .thumbnail:
            return NSSize(width: ShotzUI.Space.xs + Self.thumbSize.width + ShotzUI.Space.xs + Self.gripWidth + ShotzUI.Space.s, height: s.hitHeight)
        case .icon:
            return NSSize(width: ShotzUI.Space.xs + Self.gripWidth + ShotzUI.Space.xxs + s.iconSize + ShotzUI.Space.s, height: s.hitHeight)
        }
    }

    override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let s = shotzSize
        let chrome = chromeRect()
        let path = CGPath(roundedRect: chrome, cornerWidth: s.radius, cornerHeight: s.radius, transform: nil)
        let fills = ShotzUI.fills(for: role, state: state)
        drawChrome(path, fills: fills, state: state, in: ctx)
        let active = state.isHovered || state.isPressed
        switch style {
        case .thumbnail:
            let t = CGRect(x: chrome.minX + ShotzUI.Space.xs, y: (chrome.midY - Self.thumbSize.height / 2).rounded(),
                           width: Self.thumbSize.width, height: Self.thumbSize.height)
            drawThumbnail(in: t, ctx: ctx)
            drawGrip(x: t.maxX + ShotzUI.Space.xs, midY: chrome.midY,
                     color: active ? ShotzUI.Palette.textSecondary : ShotzUI.Palette.textTertiary, ctx: ctx)
        case .icon:
            // The grip appears on hover: "this can be picked up".
            if active { drawGrip(x: chrome.minX + ShotzUI.Space.xs, midY: chrome.midY, color: ShotzUI.Palette.textTertiary, ctx: ctx) }
            let x = chrome.minX + ShotzUI.Space.xs + Self.gripWidth + ShotzUI.Space.xxs
            drawIcon(.dragHandle, in: CGRect(x: x, y: (chrome.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize),
                     color: fills.content, ctx: ctx)
        }
    }

    /// The result, aspect-fitted in a rounded frame with a hairline edge.
    private func drawThumbnail(in frame: CGRect, ctx: CGContext) {
        let radius = ShotzUI.Radius.small - 1
        let clip = CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.clip()
        ctx.setFillColor(ShotzUI.Palette.surfaceSunken.resolved(in: effectiveAppearance).cgColor)
        ctx.fill(frame)
        if let image = thumbnail, image.size.width > 0, image.size.height > 0 {
            let scale = max(frame.width / image.size.width, frame.height / image.size.height)
            let size = CGSize(width: image.size.width * scale, height: image.size.height * scale)
            let r = CGRect(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2, width: size.width, height: size.height)
            image.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: [.interpolation: NSImageInterpolation.high.rawValue])
        }
        ctx.restoreGState()
        ctx.addPath(CGPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5), cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.setStrokeColor(ShotzUI.Palette.border.resolved(in: effectiveAppearance).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
    }

    /// Two columns of three dots.
    private func drawGrip(x: CGFloat, midY: CGFloat, color: NSColor, ctx: CGContext) {
        ctx.setFillColor(color.resolved(in: effectiveAppearance).cgColor)
        let d: CGFloat = 2
        for col in 0..<2 {
            for row in -1...1 {
                ctx.fillEllipse(in: CGRect(x: x + CGFloat(col) * 4, y: (midY + CGFloat(row) * 4 - d / 2).rounded(), width: d, height: d))
            }
        }
    }
}
