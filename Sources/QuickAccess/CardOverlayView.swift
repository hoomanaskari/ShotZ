import AppKit

/// Hover controls (SPEC §4.3) and the Copied/Saved confirmation, laid over a card.
///
/// Layout: Close top-left, Annotate top-right, Quick Look bottom-right, the
/// pixel-size caption bottom-left, Copy and Save as a centred pair of pills.
@MainActor final class CardOverlayView: NSView {
    var onAction: ((CardAction) -> Void)?

    private let style: CardStyle
    private let controls = NSView()
    private let scrim = CAGradientLayer()
    private let buttons: [CardButton]
    private let captionChip = GlassView()
    private let caption = NSTextField(labelWithString: "")
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
        controls.layer?.addSublayer(scrim)
        scrim.locations = [0, 0.38, 0.62, 1]
        addSubview(controls)
        caption.stringValue = captionText
        caption.font = style.captionFont
        caption.textColor = .labelColor
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
        scrim.colors = [palette.scrimEdge, palette.scrimMiddle, palette.scrimMiddle, palette.scrimEdge]
        flash.apply(palette, font: style.pillFont)
    }

    /// ≤120 ms (SPEC §4.3 asks for ≤100 ms to appear).
    func setRevealed(_ revealed: Bool, animated: Bool = true) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? (revealed ? 0.09 : 0.12) : 0
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ctx.allowsImplicitAnimation = true
            controls.animator().alphaValue = revealed ? 1 : 0
        }
    }

    /// The pressed look on the button for `action` (keyboard shortcuts).
    func showPressed(_ action: CardAction) {
        guard isRevealed else { return }
        buttons.first { $0.action == action }?.flashPressed()
    }

    /// Shows a short confirmation in the centre of the card.
    func showFlash(_ text: String, success: Bool) {
        flash.configure(text: text, success: success)
        needsLayout = true
        layoutSubtreeIfNeeded()
        flashGeneration += 1
        let generation = flashGeneration
        controls.alphaValue = 0
        isRevealed = false
        flash.alphaValue = 1
        if let layer = flash.layer {
            let pop = CASpringAnimation(perceptualDuration: 0.3, bounce: 0.25)
            pop.keyPath = "transform.scale"
            pop.fromValue = 0.86
            pop.toValue = 1
            pop.duration = pop.settlingDuration
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 0
            fade.toValue = 1
            fade.duration = 0.1
            layer.add(pop, forKey: "pop")
            layer.add(fade, forKey: "fadeIn")
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self] in
            guard let self, self.flashGeneration == generation else { return }
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                self.flash.animator().alphaValue = 0
            }
        }
    }

    override func layout() {
        super.layout()
        let s = style
        let b = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controls.frame = b
        scrim.frame = b
        CATransaction.commit()

        let chip = CGSize(width: s.chip, height: s.chip)
        func place(_ action: CardAction, _ origin: CGPoint) {
            buttons.first { $0.action == action }?.frame = CGRect(origin: origin, size: chip)
        }
        let top = b.maxY - s.chipInset - s.chip
        place(.close, CGPoint(x: s.chipInset, y: top))
        place(.annotate, CGPoint(x: b.maxX - s.chipInset - s.chip, y: top))
        place(.quickLook, CGPoint(x: b.maxX - s.chipInset - s.chip, y: s.chipInset))

        // Caption centred on the Quick Look button's row.
        let t = caption.intrinsicContentSize
        let capH = s.captionHeight
        let padX = (capH * 0.45).rounded()
        captionChip.frame = CGRect(x: s.chipInset, y: (s.chipInset + (s.chip - capH) / 2).rounded(), width: (t.width + padX * 2).rounded(.up), height: capH)
        caption.frame = CGRect(x: padX, y: ((capH - t.height) / 2).rounded(), width: t.width + 1, height: t.height)

        // Copy and Save: equal widths, centred, never wider than the card allows.
        let pills = buttons.filter { $0.action == .copy || $0.action == .save }
        let natural = pills.map(\.pillWidth).max() ?? 0
        let pillW = min(natural, ((b.width - 2 * s.chipInset - s.pillGap) / 2).rounded(.down))
        var x = (b.midX - (pillW * 2 + s.pillGap) / 2).rounded()
        let y = (b.midY - s.pillHeight / 2).rounded()
        for pill in pills {
            pill.frame = CGRect(x: x, y: y, width: pillW, height: s.pillHeight)
            x += pillW + s.pillGap
        }
        let f = flash.fittingSize
        flash.frame = CGRect(x: (b.midX - f.width / 2).rounded(), y: (b.midY - f.height / 2).rounded(), width: f.width, height: f.height)
    }

    /// Only the buttons are hit targets (with their ≥28 pt hit frames), and
    /// only while revealed; everything else falls through to the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isRevealed else { return nil }
        let local = convert(point, from: superview)
        // Pills first: their hit frames never overlap the corners, but be explicit.
        for button in buttons.reversed() where button.hitFrame.contains(local) {
            return button
        }
        return nil
    }

    /// Accessibility: buttons stay reachable even when not revealed.
    override func accessibilityChildren() -> [Any]? { buttons }
}

/// The centred "Copied" / "Saved" confirmation.
@MainActor final class FlashBadgeView: NSView {
    private let glass = GlassView()
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var palette: CardStyle.Palette?
    private var success = true

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        addSubview(glass)
        glass.addSubview(icon)
        glass.addSubview(label)
        label.textColor = .labelColor
        layer?.shadowColor = .black
        layer?.shadowOpacity = 0.25
        layer?.shadowRadius = 8
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ palette: CardStyle.Palette, font: NSFont) {
        self.palette = palette
        label.font = font
        icon.contentTintColor = success ? palette.accentInk : palette.failureInk
    }

    func configure(text: String, success: Bool) {
        self.success = success
        label.stringValue = text
        icon.image = (success ? CardIcon.success : .failure).image(pointSize: 18)
        if let palette { icon.contentTintColor = success ? palette.accentInk : palette.failureInk }
        setAccessibilityLabel(text)
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
    }

    override var fittingSize: NSSize {
        let t = label.intrinsicContentSize
        return NSSize(width: (12 + 18 + 7 + t.width + 15).rounded(.up), height: 32)
    }

    override func layout() {
        super.layout()
        glass.frame = bounds
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: bounds.height / 2, cornerHeight: bounds.height / 2, transform: nil)
        icon.frame = CGRect(x: 12, y: 0, width: 18, height: bounds.height)
        let t = label.intrinsicContentSize
        label.frame = CGRect(x: 37, y: ((bounds.height - t.height) / 2).rounded(), width: t.width + 2, height: t.height)
    }
}
