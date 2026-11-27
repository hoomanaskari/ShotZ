import AppKit
import ShotzCore

/// A slider with an optional leading icon and a trailing monospaced value, e.g. opacity:
/// [drop-half] ───●──── 80 %. Click anywhere on the track to jump; arrow keys step.
@MainActor
public final class ShotzSlider: ShotzControlView {
    public var value: Double { didSet { value = min(max(value, minValue), maxValue); needsDisplay = true; setAccessibilityValue(formatted) } }
    public var minValue: Double
    public var maxValue: Double
    /// Arrow-key step.
    public var step: Double
    public var icon: ShotzIcon? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Formats the trailing value; nil hides it. Default: percent of the range.
    public var format: ((Double) -> String)? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Widest string the formatter produces, so the track never changes length.
    public var valuePlaceholder = "100 %" { didSet { invalidateIntrinsicContentSize() } }
    /// Every value change, live during a drag.
    public var onChange: ((Double) -> Void)?
    /// The settled value: once when a press ends (if it changed the value) and after each key or
    /// accessibility step. A drag is many `onChange` calls and one `onCommit`.
    public var onCommit: ((Double) -> Void)?
    private var changedDuringPress = false
    public var trackWidth: CGFloat = 120 { didSet { invalidateIntrinsicContentSize() } }

    public init(value: Double, in range: ClosedRange<Double> = 0...1, step: Double = 0.05, icon: ShotzIcon? = nil, label: String,
                size: ShotzUI.ControlSize = .regular) {
        self.value = value
        self.minValue = range.lowerBound
        self.maxValue = range.upperBound
        self.step = step
        self.icon = icon
        super.init(frame: .zero)
        shotzSize = size
        format = { [minValue, maxValue] v in "\(Int(((v - minValue) / (maxValue - minValue) * 100).rounded())) %" }
        setAccessibilityRole(.slider)
        setAccessibilityLabel(label)
        setAccessibilityValue(formatted)
    }

    private var formatted: String { format?(value) ?? String(value) }
    private let knob: CGFloat = 16
    private var valueWidth: CGFloat {
        guard format != nil else { return 0 }
        return ceil((valuePlaceholder as NSString).size(withAttributes: [.font: ShotzUI.Typography.value.font]).width)
    }

    public override var intrinsicContentSize: NSSize {
        let s = shotzSize
        let w = (icon != nil ? s.iconSize + ShotzUI.Space.s : 0) + trackWidth + (format != nil ? ShotzUI.Space.s + valueWidth : 0)
        return NSSize(width: ceil(w), height: s.hitHeight)
    }

    /// The track, in the slider's coordinates (internal: tests aim at points along it).
    var trackRect: CGRect {
        let s = shotzSize
        let left = (icon != nil ? s.iconSize + ShotzUI.Space.s : 0) + knob / 2
        let right = (format != nil ? ShotzUI.Space.s + valueWidth : 0) + knob / 2
        return CGRect(x: left, y: (bounds.midY - 2).rounded(), width: max(bounds.width - left - right, 1), height: 4)
    }

    private var fraction: CGFloat { maxValue > minValue ? CGFloat((value - minValue) / (maxValue - minValue)) : 0 }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let a = effectiveAppearance, s = shotzSize, P = ShotzUI.Palette.self
        let content: NSColor = state.isEnabled ? P.textSecondary : P.textTertiary
        if let icon {
            drawIcon(icon, in: CGRect(x: 0, y: (bounds.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize), color: content, ctx: ctx)
        }
        let track = trackRect
        ctx.addPath(CGPath(roundedRect: track, cornerWidth: 2, cornerHeight: 2, transform: nil))
        ctx.setFillColor(P.fillPressed.resolved(in: a).cgColor)
        ctx.fillPath()
        let filled = CGRect(x: track.minX, y: track.minY, width: track.width * fraction, height: track.height)
        if filled.width > 0 {
            ctx.addPath(CGPath(roundedRect: filled, cornerWidth: 2, cornerHeight: 2, transform: nil))
            ctx.setFillColor((state.isEnabled ? P.accentFill : P.textTertiary).resolved(in: a).cgColor)
            ctx.fillPath()
        }
        let cx = track.minX + track.width * fraction
        let knobRect = CGRect(x: (cx - knob / 2).rounded(), y: (bounds.midY - knob / 2).rounded(), width: knob, height: knob)
        let knobPath = CGPath(ellipseIn: knobRect, transform: nil)
        let knobFill = NSColor(name: nil) { ap in P.variant(ap).isDark ? P.hex(0xE8E8EC) : .white }
        var fills = ShotzUI.ControlFills(background: knobFill, border: P.border, content: content, raised: true)
        if state.isPressed { fills.background = knobFill.shotzDarkened(0.06) }
        if !state.isEnabled { fills.raised = false; fills.background = knobFill.withAlphaComponent(0.6) }
        drawChrome(knobPath, fills: fills, state: ShotzUI.ControlState(isEnabled: state.isEnabled), in: ctx)
        if state.isFocused { drawFocusRing(knobPath, in: ctx) }
        if format != nil {
            let attrs: [NSAttributedString.Key: Any] = [.font: ShotzUI.Typography.value.font, .foregroundColor: content]
            let text = formatted as NSString
            let size = text.size(withAttributes: attrs)
            text.draw(at: CGPoint(x: (bounds.width - size.width).rounded(), y: (bounds.midY - size.height / 2).rounded()), withAttributes: attrs)
        }
    }

    private func setValue(atX x: CGFloat) {
        let t = trackRect
        let f = min(max((x - t.minX) / t.width, 0), 1)
        let v = minValue + Double(f) * (maxValue - minValue)
        if v != value { value = v; changedDuringPress = true; onChange?(value); sendAction(action, to: target) }
    }

    public override func mouseDownAt(_ point: CGPoint) { changedDuringPress = false; setValue(atX: point.x) }
    public override func mouseDraggedTo(_ point: CGPoint) { setValue(atX: point.x) }
    public override func activate(at point: CGPoint) { onAction?(self) }
    public override func trackingEnded() {
        if changedDuringPress { changedDuringPress = false; onCommit?(value) }
    }

    private func step(by delta: Double) {
        value += delta
        onChange?(value)
        onCommit?(value)
        sendAction(action, to: target)
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123, 125: step(by: -step)
        case 124, 126: step(by: step)
        default: super.keyDown(with: event)
        }
    }

    public override func accessibilityPerformIncrement() -> Bool { step(by: step); return true }
    public override func accessibilityPerformDecrement() -> Bool { step(by: -step); return true }
}
