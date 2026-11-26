import AppKit

/// A chip or pill on the hover overlay: symbol plus optional label.
/// Layer-drawn; tracks its own press so it works in a non-key panel.
@MainActor final class CardButton: NSView {
    let action: CardAction
    var onPress: ((CardAction) -> Void)?

    private let iconView = NSImageView()
    private let label: NSTextField?
    private var pressed = false { didSet { updateColors() } }
    private var palette: CardStyle.Palette?

    init(action: CardAction, showsTitle: Bool, style: CardStyle) {
        self.action = action
        label = showsTitle ? NSTextField(labelWithString: action.title) : nil
        super.init(frame: .zero)
        wantsLayer = true
        layer?.borderWidth = 0.5
        let config = NSImage.SymbolConfiguration(pointSize: style.symbolPointSize, weight: .semibold)
        iconView.image = NSImage(systemSymbolName: action.symbolName, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
        iconView.imageScaling = .scaleNone
        addSubview(iconView)
        if let label {
            label.font = style.pillFont
            label.alignment = .left
            addSubview(label)
        }
        toolTip = action.tooltip
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Natural size for a pill; chips are sized by the overlay.
    func pillWidth(height: CGFloat) -> CGFloat {
        guard let label else { return height }
        return (12 + 14 + 5 + label.intrinsicContentSize.width + 13).rounded(.up)
    }

    func apply(_ palette: CardStyle.Palette) {
        self.palette = palette
        iconView.contentTintColor = palette.chipInk
        label?.textColor = palette.chipInk
        layer?.borderColor = palette.chipStroke
        updateColors()
    }

    private func updateColors() {
        guard let palette else { return }
        layer?.backgroundColor = pressed ? palette.chipPressed : palette.chipFill
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        if let label {
            let iconW: CGFloat = 14
            iconView.frame = CGRect(x: 12, y: 0, width: iconW, height: bounds.height)
            let size = label.intrinsicContentSize
            label.frame = CGRect(x: 12 + iconW + 5, y: ((bounds.height - size.height) / 2).rounded(), width: size.width + 2, height: size.height)
        } else {
            iconView.frame = bounds
        }
    }

    // MARK: Mouse

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseDown(with event: NSEvent) { pressed = true }

    override func mouseDragged(with event: NSEvent) {
        pressed = bounds.contains(convert(event.locationInWindow, from: nil))
    }

    override func mouseUp(with event: NSEvent) {
        let inside = bounds.contains(convert(event.locationInWindow, from: nil))
        pressed = false
        if inside { onPress?(action) }
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
