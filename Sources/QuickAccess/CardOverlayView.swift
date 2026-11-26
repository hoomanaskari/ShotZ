import AppKit
import ShotzCore
import ShotzUI

/// Hover controls (SPEC §4.3) and the Copied/Saved confirmation, laid over a
/// card, built from ShotzUI glass controls as in `StackCardHover`: Close
/// top-left, Annotate top-right, Quick Look bottom-right, the pixel-size
/// caption bottom-left, Copy and Save as a centred, equal-width pair.
@MainActor final class CardOverlayView: NSView {
    var onAction: ((CardAction) -> Void)?

    private let style: CardStyle
    private let controls = NSView()
    private let scrim = CALayer()
    /// The five action buttons, in a fixed order.
    let buttons: [(action: CardAction, button: ShotzButton)]
    /// TEMP until ShotzUI has a caption-pill variant: a frozen, non-interactive
    /// compact glass button (never a hit target, reports itself as text).
    /// nil on sizes that don't show a caption.
    private let caption: ShotzButton?
    /// Copy and Save carry their labels (false: icon-only circles).
    let pairIsLabelled: Bool
    private var toast: ShotzToast?
    private(set) var isRevealed = false
    private var flashGeneration = 0

    init(style: CardStyle, captionText: String, cardSize: CGSize) {
        self.style = style
        func corner(_ action: CardAction, _ icon: ShotzIcon) -> (CardAction, ShotzButton) {
            (action, ShotzButton(icon: icon, role: .glass, size: style.cornerSize))
        }
        func pill(_ action: CardAction, _ icon: ShotzIcon) -> (CardAction, ShotzButton) {
            (action, ShotzButton(title: action.title, icon: icon, role: .glass, size: style.pillSize))
        }
        buttons = [
            corner(.close, CardIcon.action(.close).shotzIcon),
            corner(.annotate, CardIcon.action(.annotate).shotzIcon),
            corner(.quickLook, CardIcon.action(.quickLook).shotzIcon),
            pill(.copy, CardIcon.action(.copy).shotzIcon),
            pill(.save, CardIcon.action(.save).shotzIcon),
        ]
        caption = style.showsCaption ? ShotzButton(title: captionText, role: .glass, size: .compact) : nil
        pairIsLabelled = style.allowsLabels && Self.labelledPairFits(buttons.filter { $0.0 == .copy }.map(\.1).first, style: style, cardSize: cardSize)
        super.init(frame: .zero)
        wantsLayer = true
        controls.wantsLayer = true
        controls.alphaValue = 0
        controls.layer?.addSublayer(scrim)
        addSubview(controls)

        if let caption {
            caption.titleFont = ShotzUI.Typography.value.font
            caption.stateOverride = .rest
            caption.setAccessibilityRole(.staticText)
            controls.addSubview(caption)
        }
        if !pairIsLabelled {
            for (action, button) in buttons where action == .copy || action == .save {
                button.title = nil
                button.shotzSize = style.cornerSize
            }
        }

        let pair = buttons.filter { $0.action == .copy || $0.action == .save }.map(\.button)
        let pairWidth = pair.map(\.intrinsicContentSize.width).max() ?? 0
        for (action, button) in buttons {
            button.setShotzToolTip(action.title, shortcut: action.shortcutHint)
            button.setAccessibilityLabel(action.title)
            if pair.contains(where: { $0 === button }) { button.minimumWidth = pairWidth }
            button.onAction = { [weak self] _ in self?.onAction?(action) }
            controls.addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Labelled Copy/Save fit when the pair keeps `Space.s` from the card edges
    /// and its row keeps `Space.s` from the corner rows.
    static func labelledPairFits(_ sample: ShotzButton?, style: CardStyle, cardSize: CGSize) -> Bool {
        guard let sample else { return false }
        let gap = ShotzUI.Space.s
        let pairWidth = 2 * sample.intrinsicContentSize.width + gap
        let cornerHit = style.cornerSize.hitHeight
        let middle = cardSize.height - 2 * (style.hitInset + cornerHit)
        return pairWidth + 2 * gap <= cardSize.width && middle >= style.pillSize.hitHeight + 2 * gap
    }

    func apply(_ palette: CardStyle.Palette) {
        scrim.backgroundColor = CGColor(gray: 0, alpha: CardStyle.scrimOpacity)
    }

    /// Fades the controls with `Motion.fast` (0.12 s; 0 under Reduce Motion).
    func setRevealed(_ revealed: Bool, animated: Bool = true) {
        guard revealed != isRevealed else { return }
        isRevealed = revealed
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = animated ? ShotzUI.Motion.fast : 0
            ctx.timingFunction = ShotzUI.Motion.arrive
            ctx.allowsImplicitAnimation = true
            controls.animator().alphaValue = revealed ? 1 : 0
        }
    }

    func button(for action: CardAction) -> ShotzButton? {
        buttons.first { $0.action == action }?.button
    }

    /// The pressed look on the button for `action` (keyboard shortcuts).
    func showPressed(_ action: CardAction) {
        guard isRevealed, let button = button(for: action) else { return }
        button.stateOverride = .pressed
        DispatchQueue.main.asyncAfter(deadline: .now() + ShotzUI.Motion.fast) { [weak button] in
            button?.stateOverride = nil
        }
    }

    /// Shows a `ShotzToast` in the centre of the card.
    func showFlash(_ text: String, success: Bool) {
        toast?.removeFromSuperview()
        let t = ShotzToast(text, tone: success ? .success : .failure)
        toast = t
        addSubview(t)
        flashGeneration += 1
        let generation = flashGeneration
        controls.alphaValue = 0
        isRevealed = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        t.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = ShotzUI.Motion.fast
            ctx.timingFunction = ShotzUI.Motion.arrive
            t.animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.95) { [weak self, weak t] in
            guard let self, self.flashGeneration == generation, let t else { return }
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = ShotzUI.Motion.standard
                t.animator().alphaValue = 0
            }, completionHandler: { [weak t] in MainActor.assumeIsolated { t?.removeFromSuperview() } })
        }
    }

    override func layout() {
        super.layout()
        let b = bounds
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controls.frame = b
        scrim.frame = b
        CATransaction.commit()

        let inset = style.hitInset
        for (action, button) in buttons where [.close, .annotate, .quickLook].contains(action) {
            let s = button.intrinsicContentSize
            let x = action == .close ? inset : b.maxX - inset - s.width
            let y = action == .quickLook ? inset : b.maxY - inset - s.height
            button.frame = CGRect(x: x, y: y, width: s.width, height: s.height)
        }
        // Caption on the Quick Look row.
        if let caption {
            let c = caption.intrinsicContentSize
            caption.frame = CGRect(x: inset, y: inset, width: c.width, height: c.height)
        }

        let pair = buttons.filter { $0.action == .copy || $0.action == .save }.map(\.button)
        let p = pair.first?.intrinsicContentSize ?? .zero
        let gap = pairIsLabelled ? ShotzUI.Space.s : ShotzUI.Space.m
        var x = (b.midX - (2 * p.width + gap) / 2).rounded()
        let y = (b.midY - p.height / 2).rounded()
        for button in pair {
            button.frame = CGRect(x: x, y: y, width: p.width, height: p.height)
            x += p.width + gap
        }
        if let toast {
            let f = toast.intrinsicContentSize
            toast.frame = CGRect(x: (b.midX - f.width / 2).rounded(), y: (b.midY - f.height / 2).rounded(), width: f.width, height: f.height)
        }
    }

    /// Only the five action buttons are hit targets (ShotzUI frames are ≥ 28 pt),
    /// and only while revealed; everything else falls through to the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isRevealed else { return nil }
        let local = convert(point, from: superview)
        for (_, button) in buttons.reversed() where button.frame.contains(local) {
            return button
        }
        return nil
    }

    /// Every visible control's frame (buttons and caption), for layout tests.
    var controlFrames: [(name: String, frame: CGRect, natural: CGSize)] {
        var out = buttons.map { ("\($0.action)", $0.button.frame, $0.button.intrinsicContentSize) }
        if let caption { out.append(("caption", caption.frame, caption.intrinsicContentSize)) }
        return out
    }

    /// Accessibility: buttons stay reachable even when not revealed.
    override func accessibilityChildren() -> [Any]? { buttons.map(\.button) }
}
