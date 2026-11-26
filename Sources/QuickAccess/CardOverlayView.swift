import AppKit
import ShotzCore
import ShotzUI

/// Hover controls (SPEC §4.3) and the Copied/Saved confirmation, laid over a
/// card, from ShotzUI's card glass set as in `StackCardHover(cardSize:)`:
/// Close top-left, Annotate top-right, Quick Look bottom-right (glass
/// circles), the size caption bottom-left, Copy and Save centred.
///
/// Per size: Large and Medium use the labelled glass pair and the caption;
/// Small uses the icon-only glass pair and no caption.
@MainActor final class CardOverlayView: NSView {
    var onAction: ((CardAction) -> Void)?

    private let style: CardStyle
    private let controls = NSView()
    private let scrim = CALayer()
    /// The five action controls, in a fixed order.
    let buttons: [(action: CardAction, button: ShotzControlView)]
    private let caption: ShotzCaptionPill?
    private weak var toast: ShotzToast?
    private(set) var isRevealed = false
    var pairIsLabelled: Bool { style.labelledPair }

    init(style: CardStyle, captionText: String, cardSize: CGSize) {
        self.style = style
        let ui = style.ui
        func circle(_ action: CardAction) -> (CardAction, ShotzControlView) {
            (action, ShotzGlassIconButton(icon: CardIcon.action(action).shotzIcon, cardSize: ui))
        }
        func pair(_ action: CardAction) -> (CardAction, ShotzControlView) {
            (action, ShotzButton.glass(action.title, icon: CardIcon.action(action).shotzIcon, cardSize: ui, iconOnly: !style.labelledPair))
        }
        buttons = [circle(.close), circle(.annotate), circle(.quickLook), pair(.copy), pair(.save)]
        caption = style.showsCaption ? ShotzCaptionPill(captionText, cardSize: ui) : nil
        super.init(frame: .zero)
        wantsLayer = true
        controls.wantsLayer = true
        controls.alphaValue = 0
        controls.layer?.addSublayer(scrim)
        addSubview(controls)
        if let caption { controls.addSubview(caption) }

        let labelled = style.labelledPair ? buttons.compactMap { $0.button as? ShotzButton } : []
        let pairWidth = labelled.map(\.intrinsicContentSize.width).max() ?? 0
        labelled.forEach { $0.minimumWidth = pairWidth }
        for (action, button) in buttons {
            button.setShotzToolTip(action.title, shortcut: action.shortcutHint)
            button.setAccessibilityLabel(action.title)
            button.onAction = { [weak self] _ in self?.onAction?(action) }
            controls.addSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func apply(_ palette: CardStyle.Palette) {
        scrim.backgroundColor = palette.scrim
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

    func button(for action: CardAction) -> ShotzControlView? {
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

    /// Shows a `ShotzToast` centred on the card; it fades out and removes itself.
    func showFlash(_ text: String, success: Bool) {
        toast?.removeFromSuperview()
        controls.alphaValue = 0
        isRevealed = false
        let t = ShotzToast(text, tone: success ? .success : .failure, compact: style.compactToast)
        toast = t
        t.show(in: self, position: .center, duration: Self.flashDuration)
    }

    /// How long a confirmation stays before fading (`closeAfterFlashDelay` closes the card meanwhile).
    static let flashDuration: TimeInterval = 0.95

    override func layout() {
        super.layout()
        let b = bounds
        let ui = style.ui
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        controls.frame = b
        scrim.frame = b
        CATransaction.commit()

        // Hit frames are ≥ 28 pt; offset so the visible circle sits `cornerInset` in.
        let side = button(for: .close)?.intrinsicContentSize.width ?? 28
        let o = ui.cornerInset - (side - ui.glassDiameter) / 2
        for (action, button) in buttons where [.close, .annotate, .quickLook].contains(action) {
            let x = action == .close ? o : b.maxX - o - side
            let y = action == .quickLook ? o : b.maxY - o - side // y-up: Quick Look at the bottom
            button.frame = CGRect(x: x, y: y, width: side, height: side)
        }
        let pair = buttons.filter { $0.action == .copy || $0.action == .save }.map(\.button)
        let p = pair.first?.intrinsicContentSize ?? .zero
        let gap = style.labelledPair ? (ui == .small ? 6 : ShotzUI.Space.s) : ShotzUI.Space.m
        var x = (b.midX - (2 * p.width + gap) / 2).rounded()
        let y = (b.midY - p.height / 2).rounded()
        for button in pair {
            button.frame = CGRect(x: x, y: y, width: p.width, height: p.height)
            x += p.width + gap
        }
        if let caption, let ql = button(for: .quickLook) {
            let c = caption.intrinsicContentSize
            caption.frame = CGRect(x: ui.cornerInset, y: (ql.frame.midY - c.height / 2).rounded(), width: c.width, height: c.height)
        }
    }

    /// Only the five action controls are hit targets (≥ 28 pt), and only while
    /// revealed; everything else falls through to the card.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard isRevealed else { return nil }
        let local = convert(point, from: superview)
        for (_, button) in buttons.reversed() where button.frame.contains(local) {
            return button
        }
        return nil
    }

    /// The visible shape of each control (glass circle, capsule, pill) and its
    /// hit frame, in overlay coordinates, for layout tests.
    var controlFrames: [(name: String, visible: CGRect, hit: CGRect, natural: CGSize)] {
        var out: [(String, CGRect, CGRect, CGSize)] = buttons.map { action, button in
            let f = button.frame
            let visible: CGRect
            if let circle = button as? ShotzGlassIconButton {
                visible = CGRect(x: f.midX - circle.diameter / 2, y: f.midY - circle.diameter / 2, width: circle.diameter, height: circle.diameter)
            } else {
                let chrome = button.chromeRect()
                visible = CGRect(x: f.minX, y: f.midY - chrome.height / 2, width: f.width, height: chrome.height)
            }
            return ("\(action)", visible, f, button.intrinsicContentSize)
        }
        if let caption { out.append(("caption", caption.frame, caption.frame, caption.intrinsicContentSize)) }
        return out
    }

    /// Accessibility: buttons stay reachable even when not revealed.
    override func accessibilityChildren() -> [Any]? { buttons.map(\.button) }
}
