import AppKit

/// A colour preset in the options bar. Draws itself (an image button in the
/// title-bar area is desaturated by AppKit while the window is inactive) and
/// shows a clear accent ring when selected.
@MainActor final class ColorSwatchControl: NSControl {
    let color: NSColor
    var isSelected: Bool { didSet { needsDisplay = true; setAccessibilityValue(isSelected ? 1 : 0) } }
    private let handler: () -> Void

    init(color: NSColor, selected: Bool, label: String, handler: @escaping () -> Void) {
        self.color = color
        isSelected = selected
        self.handler = handler
        super.init(frame: NSRect(x: 0, y: 0, width: 22, height: 22))
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
        setAccessibilityValue(selected ? 1 : 0)
        widthAnchor.constraint(equalToConstant: 22).isActive = true
        heightAnchor.constraint(equalToConstant: 22).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds
        let dot = r.insetBy(dx: 5, dy: 5)
        color.setFill()
        NSBezierPath(ovalIn: dot).fill()
        // Hairline so white and black stay visible on either appearance.
        NSColor.separatorColor.setStroke()
        let edge = NSBezierPath(ovalIn: dot.insetBy(dx: 0.25, dy: 0.25))
        edge.lineWidth = 0.5
        edge.stroke()
        if isSelected {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: r.insetBy(dx: 1.25, dy: 1.25))
            ring.lineWidth = 2
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) {
        handler()
    }

    override func accessibilityPerformPress() -> Bool {
        handler()
        return true
    }
}
