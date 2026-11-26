import AppKit

/// The primary action (Copy, Apply): an accent-filled button with white glyph and title.
/// Drawn by the editor so it reads as primary in every window state (slightly softer
/// when the window is not key), unlike a stock bezel which turns grey.
@MainActor final class ProminentButton: NSButton {
    private var hovering = false
    private var tracking: NSTrackingArea?

    init(title: String, image: NSImage?, target: AnyObject?, action: Selector?, height: CGFloat = 28) {
        super.init(frame: .zero)
        self.title = title
        self.image = image
        self.target = target
        self.action = action
        isBordered = false
        imagePosition = image == nil ? .noImage : .imageLeading
        imageHugsTitle = true
        font = .systemFont(ofSize: NSFont.systemFontSize, weight: .semibold)
        contentTintColor = .white
        attributedTitle = NSAttributedString(string: title, attributes: [.foregroundColor: NSColor.white, .font: font as Any])
        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: height).isActive = true
        setAccessibilityLabel(title)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize {
        let base = super.intrinsicContentSize
        return NSSize(width: base.width + 24, height: base.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let key = window?.isKeyWindow ?? true
        var fill = NSColor.controlAccentColor
        if isHighlighted { fill = fill.blended(withFraction: 0.18, of: .black) ?? fill }
        else if hovering { fill = fill.blended(withFraction: 0.08, of: .white) ?? fill }
        fill.withAlphaComponent(key ? 1 : 0.82).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: EditorMetrics.corner, yRadius: EditorMetrics.corner).fill()
        super.draw(dirtyRect)
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
}
