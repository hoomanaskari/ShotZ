import AppKit

/// A hairline separator between toolbar groups (vertical, 16 pt tall) or settings rows (horizontal).
@MainActor
public final class ShotzSeparator: NSView {
    public enum Orientation: Sendable { case vertical, horizontal }
    public let orientation: Orientation
    /// Length of a vertical separator; horizontal ones stretch.
    public var length: CGFloat = 16 { didSet { invalidateIntrinsicContentSize() } }

    public init(_ orientation: Orientation = .vertical) {
        self.orientation = orientation
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    public override var intrinsicContentSize: NSSize {
        orientation == .vertical ? NSSize(width: 1, height: length) : NSSize(width: NSView.noIntrinsicMetric, height: 1)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let px = 1 / max(window?.backingScaleFactor ?? 2, 1)
            ShotzUI.Palette.separator.setFill()
            if orientation == .vertical {
                let h = min(length, bounds.height)
                NSRect(x: (bounds.midX - px / 2), y: ((bounds.height - h) / 2).rounded(), width: px, height: h).fill()
            } else {
                NSRect(x: 0, y: (bounds.midY - px / 2), width: bounds.width, height: px).fill()
            }
        }
    }
}
