import AppKit

/// Hover controls (SPEC §4.3) and the Copied/Saved confirmation, laid over a card.
@MainActor final class CardOverlayView: NSView {
    var onAction: ((CardAction) -> Void)?

    private let style: CardStyle
    private let controls = NSView()
    private let dim = NSView()
    private let buttons: [CardButton]
    private let caption = NSTextField(labelWithString: "")
    private let captionChip = NSView()
    private let flash = FlashBadgeView()
    private(set) var isRevealed = false
    private var flashGeneration = 0

    init(style: CardStyle, captionText: String) {
        self.style = style
        buttons = [
            CardButton(action: .close, showsTitle: false, style: style),
            CardButton(action: .annotate, showsTitle: false, style: style),
            CardButton(action: .quickLook, showsTitle: false, style: style),
            CardButton(action: .copy, showsTitle: true, style: style),
            CardButton(action: .save, showsTitle: true, style: style),
        ]
        super.init(frame: .zero)
        wantsLayer = true
        controls.wantsLayer = true
        controls.alphaValue = 0
        dim.wantsLayer = true
        addSubview(controls)
        controls.addSubview(dim)
        captionChip.wantsLayer = true
        caption.stringValue = captionText
        caption.font = style.captionFont
        captionChip.addSubview(caption)
        controls.addSubview(captionChip)
        for button in buttons {
            button.onPress = { [weak self] in self?.onAction?($0) }
            controls.addSubview(button)
        }
        addSubview(flash)
        flash.alphaValue = 0
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ palette: CardStyle.Palette) {
        dim.layer?.backgroundColor = palette.dim
        captionChip.layer?.backgroundColor = palette.chipFill
        caption.textColor = palette.chipInk
        buttons.forEach { $0.apply(palette) }
        flash.apply(palette, font: style.pillFont)
    }

    func setRevealed(_ revealed: Bool, animated: Bool = true) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? (revealed ? 0.09 : 0.14) : 0
            ctx.allowsImplicitAnimation = true
            controls.animator().alphaValue = revealed ? 1 : 0
        }
    }

    /// Shows a short confirmation in the centre of the card.
    func showFlash(_ text: String, symbol: String, success: Bool) {
        flash.configure(text: text, symbol: symbol, success: success)
        needsLayout = true
        layoutSubtreeIfNeeded()
        flashGeneration += 1
        let generation = flashGeneration
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.1
            flash.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.flash.animator().alphaValue = 0
            }
        }
        // Hide the controls behind the badge while it shows.
        controls.alphaValue = 0
        isRevealed = false
    }

    override func layout() {
        super.layout()
        controls.frame = bounds
        dim.frame = bounds
        let s = style
        let b = bounds
        let chip = CGSize(width: s.chip, height: s.chip)
        func place(_ action: CardAction, _ origin: CGPoint) {
            buttons.first { $0.action == action }?.frame = CGRect(origin: origin, size: chip)
        }
        place(.close, CGPoint(x: s.chipInset, y: b.maxY - s.chipInset - s.chip))
        place(.annotate, CGPoint(x: b.maxX - s.chipInset - s.chip, y: b.maxY - s.chipInset - s.chip))
        place(.quickLook, CGPoint(x: b.maxX - s.chipInset - s.chip, y: s.chipInset))

        let textSize = caption.intrinsicContentSize
        let capH = (s.chip * 0.78).rounded()
        captionChip.frame = CGRect(x: s.chipInset, y: s.chipInset + (s.chip - capH) / 2, width: textSize.width + 14, height: capH)
        captionChip.layer?.cornerRadius = capH / 2
        caption.frame = CGRect(x: 7, y: ((capH - textSize.height) / 2).rounded(), width: textSize.width + 1, height: textSize.height)

        let pills = buttons.filter { $0.action == .copy || $0.action == .save }
        let gap: CGFloat = 8
        let widths = pills.map { $0.pillWidth(height: s.pillHeight) }
        let pillW = min(widths.max() ?? 0, (b.width - 2 * s.chipInset - gap) / 2)
        let total = pillW * 2 + gap
        var x = (b.midX - total / 2).rounded()
        let y = (b.midY - s.pillHeight / 2).rounded()
        for pill in pills {
            pill.frame = CGRect(x: x, y: y, width: pillW, height: s.pillHeight)
            x += pillW + gap
        }
        let flashSize = flash.fittingSize
        flash.frame = CGRect(x: (b.midX - flashSize.width / 2).rounded(), y: (b.midY - flashSize.height / 2).rounded(), width: flashSize.width, height: flashSize.height)
    }

    /// Only the buttons are hit targets, and only while revealed; everything
    /// else falls through to the card (drag, double-click, context menu).
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isRevealed else { return nil }
        let local = convert(point, from: superview)
        for button in buttons where button.frame.contains(local) {
            return button
        }
        return nil
    }

    /// Accessibility: buttons stay reachable even when not revealed.
    override func accessibilityChildren() -> [Any]? { buttons }
}

/// The centred "Copied" / "Saved" badge.
@MainActor final class FlashBadgeView: NSView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var palette: CardStyle.Palette?
    private var success = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(icon)
        addSubview(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ palette: CardStyle.Palette, font: NSFont) {
        self.palette = palette
        label.font = font
        layer?.backgroundColor = palette.chipFill
        layer?.borderColor = palette.chipStroke
        layer?.borderWidth = 0.5
        label.textColor = palette.chipInk
        icon.contentTintColor = success ? palette.accentInk : palette.failureInk
    }

    func configure(text: String, symbol: String, success: Bool) {
        self.success = success
        label.stringValue = text
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .bold)
        icon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        if let palette { icon.contentTintColor = success ? palette.accentInk : palette.failureInk }
        setAccessibilityLabel(text)
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    override var fittingSize: NSSize {
        let t = label.intrinsicContentSize
        return NSSize(width: (12 + 16 + 6 + t.width + 14).rounded(.up), height: 30)
    }

    override func layout() {
        super.layout()
        layer?.cornerRadius = bounds.height / 2
        icon.frame = CGRect(x: 12, y: 0, width: 16, height: bounds.height)
        let t = label.intrinsicContentSize
        label.frame = CGRect(x: 34, y: ((bounds.height - t.height) / 2).rounded(), width: t.width + 2, height: t.height)
    }
}
