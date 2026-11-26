import AppKit

/// A round icon button or a labelled pill on the hover overlay. Glass
/// material, pointer-over and pressed states; tracks its own press so it
/// works in a panel that is not key. Its hit target is never under 28 pt.
@MainActor final class CardButton: NSView {
    static let minimumHitSize: CGFloat = 28

    let action: CardAction
    var onPress: ((CardAction) -> Void)?

    private let glass = GlassView()
    private let iconView = NSImageView()
    private let label: NSTextField?
    private let style: CardStyle
    private var trackingArea: NSTrackingArea?
    private var pressed = false { didSet { updateState() } }
    private var pointerInside = false { didSet { updateState() } }

    init(action: CardAction, showsTitle: Bool, style: CardStyle) {
        self.action = action
        self.style = style
        label = showsTitle ? NSTextField(labelWithString: action.title) : nil
        super.init(frame: .zero)
        wantsLayer = true
        addSubview(glass)
        iconView.image = CardIcon.action(action).image(pointSize: showsTitle ? style.pillIconSize : style.chipIconSize)
        iconView.imageScaling = .scaleNone
        iconView.contentTintColor = .labelColor
        glass.addSubview(iconView)
        if let label {
            label.font = style.pillFont
            label.textColor = .labelColor
            label.lineBreakMode = .byClipping
            glass.addSubview(label)
        }
        toolTip = action.tooltip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Natural width of a pill at the style's pill height.
    var pillWidth: CGFloat {
        guard let label else { return style.chip }
        let pad = style.pillHeight * 0.42
        return (pad + style.pillIconSize + 4 + label.intrinsicContentSize.width + pad + 2).rounded(.up)
    }

    /// The (possibly larger) rectangle that counts as a hit, in the superview.
    var hitFrame: CGRect {
        let dx = max(0, (Self.minimumHitSize - frame.width) / 2)
        let dy = max(0, (Self.minimumHitSize - frame.height) / 2)
        return frame.insetBy(dx: -dx, dy: -dy)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        let iconSize = label == nil ? style.chipIconSize : style.pillIconSize
        if let label {
            let pad = (bounds.height * 0.42).rounded()
            let t = label.intrinsicContentSize
            let content = iconSize + 4 + t.width
            let x0 = ((bounds.width - content) / 2).rounded()
            iconView.frame = CGRect(x: x0, y: 0, width: iconSize + 2, height: bounds.height)
            label.frame = CGRect(x: x0 + iconSize + 4, y: ((bounds.height - t.height) / 2).rounded(), width: min(t.width + 2, bounds.width - pad), height: t.height)
        } else {
            iconView.frame = bounds
        }
    }

    private func updateState() {
        glass.emphasis = pressed && pointerInside ? 2 : (pointerInside ? 1 : 0)
        let scale: CGFloat = pressed && pointerInside ? 0.94 : 1
        guard let layer else { return }
        let b = layer.bounds
        let t = CATransform3DTranslate(CATransform3DScale(CATransform3DMakeTranslation(b.midX, b.midY, 0), scale, scale, 1), -b.midX, -b.midY, 0)
        CATransaction.begin()
        CATransaction.setAnimationDuration(pressed ? 0.05 : 0.12)
        layer.sublayerTransform = t
        CATransaction.commit()
    }

    // MARK: Mouse

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self, userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) { pointerInside = true }
    override func mouseExited(with event: NSEvent) { pointerInside = false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) {
        pointerInside = true
        pressed = true
    }

    override func mouseDragged(with event: NSEvent) {
        pointerInside = hitBounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = hitBounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onPress?(action) }
    }

    private var hitBounds: CGRect { convert(hitFrame, from: superview) }

    /// Shown pressed briefly when the action came from a shortcut.
    func flashPressed() {
        pointerInside = true
        pressed = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { [weak self] in
            self?.pressed = false
            self?.pointerInside = false
        }
    }

    // MARK: Accessibility

    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func accessibilityLabel() -> String? { action.title }
    override func accessibilityHelp() -> String? { action.shortcutHint.map { String(localized: "Shortcut \($0) while hovering") } }
    override func accessibilityPerformPress() -> Bool {
        onPress?(action)
        return true
    }
}
