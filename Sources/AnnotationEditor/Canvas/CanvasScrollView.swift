import AppKit

/// Keeps the document centred when it is smaller than the visible area.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let doc = documentView else { return rect }
        let docFrame = doc.frame
        if rect.width > docFrame.width { rect.origin.x = docFrame.midX - rect.width / 2 }
        if rect.height > docFrame.height { rect.origin.y = docFrame.midY - rect.height / 2 }
        return rect
    }
}

/// Magnifying scroll view: pinch and ⌘-scroll zoom about the pointer,
/// two-finger scroll pans.
@MainActor final class CanvasScrollView: NSScrollView {
    /// Called when a ⌘-scroll zoom step ends (to re-rasterise).
    var onZoomSettled: (() -> Void)?
    private var settleWork: DispatchWorkItem?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        let clip = CenteringClipView()
        clip.drawsBackground = false
        contentView = clip
        hasVerticalScroller = true
        hasHorizontalScroller = true
        autohidesScrollers = true
        allowsMagnification = true
        drawsBackground = false
        scrollerStyle = .overlay
        usesPredominantAxisScrolling = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func scrollWheel(with event: NSEvent) {
        guard event.modifierFlags.contains(.command) else {
            super.scrollWheel(with: event)
            return
        }
        let delta = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY * 0.01 : event.scrollingDeltaY * 0.1
        guard delta != 0, let doc = documentView else { return }
        let point = doc.convert(event.locationInWindow, from: nil)
        let target = min(max(magnification * (1 + delta), minMagnification), maxMagnification)
        setMagnification(target, centeredAt: point)
        settleWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.onZoomSettled?() }
        settleWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }
}
