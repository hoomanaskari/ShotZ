import AppKit

/// The material behind every control on a card: a small vibrant blur of the
/// card image, adapting to light and dark, with a crisp hairline rim.
@MainActor final class GlassView: NSVisualEffectView {
    private let rim = CALayer()
    private let highlight = CALayer()
    /// Body colour over the blur, so labels stay legible on busy images.
    private let fill = CALayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        material = .hudWindow
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.masksToBounds = true
        layer?.cornerCurve = .continuous
        layer?.addSublayer(fill)
        highlight.opacity = 0
        layer?.addSublayer(highlight)
        rim.borderWidth = 0.5
        layer?.addSublayer(rim)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// 0 = resting, 1 = pointer over, 2 = pressed.
    var emphasis = 0 { didSet { updateHighlight() } }

    override func layout() {
        super.layout()
        let r = bounds.height / 2
        layer?.cornerRadius = r
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        fill.frame = bounds
        highlight.frame = bounds
        rim.frame = bounds
        rim.cornerRadius = r
        rim.cornerCurve = .continuous
        CATransaction.commit()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateColors()
    }

    private var isDark: Bool { effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }

    private func updateColors() {
        // Light: a bright frosted chip; dark: a smoky one. Material does the blur.
        material = isDark ? .hudWindow : .popover
        rim.borderColor = isDark ? CGColor(gray: 1, alpha: 0.16) : CGColor(gray: 0, alpha: 0.10)
        fill.backgroundColor = isDark ? CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.62) : CGColor(gray: 1, alpha: 0.68)
        updateHighlight()
    }

    private func updateHighlight() {
        let tint: CGColor = isDark ? CGColor(gray: 1, alpha: 1) : CGColor(gray: 0, alpha: 1)
        CATransaction.begin()
        CATransaction.setAnimationDuration(emphasis == 2 ? 0.04 : 0.1)
        highlight.backgroundColor = tint
        highlight.opacity = [0, 0.08, 0.16][min(max(emphasis, 0), 2)]
        CATransaction.commit()
    }
}
