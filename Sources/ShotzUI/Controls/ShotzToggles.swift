import AppKit
import ShotzCore

/// ShotZ's checkbox (AppKit): 14-pt rounded square, accent with a check when on, label to the right.
@MainActor
public final class ShotzCheckbox: ShotzControlView {
    public var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(title) } }
    public var isOn: Bool {
        get { isSelected }
        set { isSelected = newValue }
    }
    public var onToggle: ((Bool) -> Void)?

    public init(_ title: String, isOn: Bool = false) {
        self.title = title
        super.init(frame: .zero)
        isSelected = isOn
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        setAccessibilityValue(isOn ? 1 : 0)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: 14 + ShotzUI.Space.s + ceil((title as NSString).size(withAttributes: [.font: ShotzUI.Typography.body.font]).width) + 2, height: 28)
    }

    public override func selectionChanged() { setAccessibilityValue(isSelected ? 1 : 0) }
    public override func activate(at point: CGPoint) { isSelected.toggle(); onToggle?(isSelected); super.activate(at: point) }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let P = ShotzUI.Palette.self
        let box = CGRect(x: 0, y: (bounds.midY - 7).rounded(), width: 14, height: 14)
        let path = CGPath(roundedRect: box, cornerWidth: 4, cornerHeight: 4, transform: nil)
        var fills = state.isSelected
            ? ShotzUI.ControlFills(background: P.accentFill, border: P.accentEdge, content: P.onAccent, raised: false)
            : ShotzUI.ControlFills(background: P.secondaryFill, border: P.border, content: P.textPrimary, raised: true)
        if state.isPressed { fills.background = fills.background?.shotzDarkened(0.08) }
        if !state.isEnabled { fills.background = fills.background?.withAlphaComponent(0.5); fills.raised = false }
        drawChrome(path, fills: fills, state: state, in: ctx)
        if state.isSelected { drawIcon(.check, in: box.insetBy(dx: 1.5, dy: 1.5), color: fills.content, ctx: ctx) }
        let color = state.isEnabled ? P.textPrimary : P.textTertiary
        let attrs: [NSAttributedString.Key: Any] = [.font: ShotzUI.Typography.body.font, .foregroundColor: color]
        let s = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: CGPoint(x: 14 + ShotzUI.Space.s, y: (bounds.midY - s.height / 2).rounded()), withAttributes: attrs)
    }
}

/// ShotZ's switch (AppKit): 32 × 18 capsule, accent when on, white knob. Same look as `.shotzSwitch`.
@MainActor
public final class ShotzSwitch: ShotzControlView {
    public var isOn: Bool {
        get { isSelected }
        set { isSelected = newValue }
    }
    public var onToggle: ((Bool) -> Void)?
    /// Knob position 0 (off) … 1 (on), animated.
    @objc public dynamic var knob: CGFloat = 0 { didSet { needsDisplay = true } }

    public init(isOn: Bool = false, label: String) {
        super.init(frame: .zero)
        isSelected = isOn
        knob = isOn ? 1 : 0
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(label)
        setAccessibilityValue(isOn ? 1 : 0)
    }

    public override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "knob" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    public override var intrinsicContentSize: NSSize { NSSize(width: 36, height: 28) }

    public override func selectionChanged() {
        setAccessibilityValue(isSelected ? 1 : 0)
        let target: CGFloat = isSelected ? 1 : 0
        if window != nil, ShotzUI.Motion.fast > 0 {
            NSAnimationContext.runAnimationGroup { $0.duration = ShotzUI.Motion.fast * 1.3; animator().knob = target }
        } else {
            knob = target
        }
    }

    public override func activate(at point: CGPoint) { isSelected.toggle(); onToggle?(isSelected); super.activate(at: point) }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let P = ShotzUI.Palette.self, a = effectiveAppearance
        let k = stateOverride != nil ? (state.isSelected ? 1 : 0) : knob
        let track = CGRect(x: ((bounds.width - 32) / 2).rounded(), y: (bounds.midY - 9).rounded(), width: 32, height: 18)
        let path = CGPath(roundedRect: track, cornerWidth: 9, cornerHeight: 9, transform: nil)
        ctx.saveGState()
        if !state.isEnabled { ctx.setAlpha(0.45) }
        let off = P.fillPressed.resolved(in: a), on = P.accentFill.resolved(in: a)
        ctx.addPath(path)
        ctx.setFillColor(off.mixed(with: on, k).withAlphaComponent(off.alphaComponent + (1 - off.alphaComponent) * k).cgColor)
        ctx.fillPath()
        let knobRect = CGRect(x: track.minX + 2 + (track.width - 18) * k, y: track.minY + 2, width: 14, height: 14)
        ctx.setShadow(offset: CGSize(width: 0, height: -0.5), blur: 1.5, color: NSColor.black.withAlphaComponent(0.25).cgColor)
        ctx.setFillColor(state.isPressed ? NSColor(white: 0.93, alpha: 1).cgColor : NSColor.white.cgColor)
        ctx.fillEllipse(in: knobRect)
        ctx.restoreGState()
        if state.isFocused { drawFocusRing(path, in: ctx) }
    }
}

/// A single colour well: a swatch (with a hue ring when it's a custom colour). Click to edit
/// (the caller opens the colour panel via `onAction`).
@MainActor
public final class ShotzColorWell: ShotzControlView {
    public var color: NSColor { didSet { needsDisplay = true } }
    public var showsHueRing: Bool { didSet { needsDisplay = true } }

    public init(color: NSColor, showsHueRing: Bool = true, label: String) {
        self.color = color
        self.showsHueRing = showsHueRing
        super.init(frame: .zero)
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel(label)
    }

    public override var intrinsicContentSize: NSSize { NSSize(width: 28, height: 28) }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let d: CGFloat = 20
        let r = CGRect(x: ((bounds.width - d) / 2).rounded(), y: ((bounds.height - d) / 2).rounded(), width: d, height: d)
        if state.isHovered || state.isPressed {
            ctx.setFillColor((state.isPressed ? ShotzUI.Palette.fillPressed : ShotzUI.Palette.fillHover).resolved(in: effectiveAppearance).cgColor)
            ctx.fillEllipse(in: r.insetBy(dx: -4, dy: -4))
        }
        ctx.saveGState()
        if !state.isEnabled { ctx.setAlpha(0.4) }
        if showsHueRing {
            let steps = 48
            ctx.setLineWidth(3)
            for i in 0..<steps {
                let a0 = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(steps) * 2 * .pi
                ctx.setStrokeColor(NSColor(hue: CGFloat(i) / CGFloat(steps), saturation: 0.72, brightness: 0.95, alpha: 1).cgColor)
                ctx.addArc(center: CGPoint(x: r.midX, y: r.midY), radius: d / 2 - 1.5, startAngle: a0, endAngle: a0 + 2 * .pi / CGFloat(steps) + 0.02, clockwise: false)
                ctx.strokePath()
            }
            ctx.setFillColor(color.resolved(in: effectiveAppearance).cgColor)
            ctx.fillEllipse(in: r.insetBy(dx: 4.5, dy: 4.5))
        } else {
            ctx.setFillColor(color.resolved(in: effectiveAppearance).cgColor)
            ctx.fillEllipse(in: r)
            ctx.setStrokeColor(ShotzUI.Palette.swatchEdge.resolved(in: effectiveAppearance).cgColor)
            ctx.setLineWidth(1)
            ctx.strokeEllipse(in: r.insetBy(dx: 0.5, dy: 0.5))
        }
        ctx.restoreGState()
        if state.isFocused { drawFocusRing(CGPath(ellipseIn: r, transform: nil), in: ctx) }
    }
}

/// An image tile (gradient presets, wallpapers): rounded thumbnail with the neutral selection ring.
@MainActor
public final class ShotzTileButton: ShotzControlView {
    public var image: NSImage { didSet { needsDisplay = true } }
    public var tileSize: CGSize { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    public init(image: NSImage, size: CGSize = CGSize(width: 36, height: 24), label: String) {
        self.image = image
        self.tileSize = size
        super.init(frame: .zero)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(label)
    }

    public override var intrinsicContentSize: NSSize { NSSize(width: tileSize.width + 8, height: max(tileSize.height + 8, 28)) }
    public override func selectionChanged() { setAccessibilityValue(isSelected ? 1 : 0) }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let r = CGRect(x: ((bounds.width - tileSize.width) / 2).rounded(), y: ((bounds.height - tileSize.height) / 2).rounded(), width: tileSize.width, height: tileSize.height)
        let a = effectiveAppearance
        let tile = NSBezierPath(roundedRect: r, xRadius: ShotzUI.Radius.small + 1, yRadius: ShotzUI.Radius.small + 1)
        NSGraphicsContext.saveGraphicsState()
        if !state.isEnabled { ctx.setAlpha(0.4) }
        tile.addClip()
        image.draw(in: r, from: .zero, operation: .sourceOver, fraction: state.isPressed ? 0.85 : 1)
        NSGraphicsContext.restoreGraphicsState()
        ctx.addPath(CGPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), cornerWidth: 5, cornerHeight: 5, transform: nil))
        ctx.setStrokeColor(ShotzUI.Palette.swatchEdge.resolved(in: a).cgColor)
        ctx.setLineWidth(1)
        ctx.strokePath()
        let ring = CGPath(roundedRect: r.insetBy(dx: -3, dy: -3), cornerWidth: 8, cornerHeight: 8, transform: nil)
        if state.isSelected || state.isHovered {
            ctx.addPath(ring)
            ctx.setStrokeColor((state.isSelected ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textTertiary).resolved(in: a).cgColor)
            ctx.setLineWidth(state.isSelected ? 2 : 1.5)
            ctx.strokePath()
        }
        if state.isFocused { drawFocusRing(ring, in: ctx) }
    }
}

extension ShotzUI {
    public enum LabelRole: Sendable {
        /// Panel and popover titles (section header style).
        case panelTitle
        /// Right-aligned labels in a form column.
        case formLabel
        /// Wrapping secondary notes under controls.
        case note
        /// Small captions (values, hints).
        case caption
    }

    /// A non-editable text label styled for `role`. Use instead of hand-styled `NSTextField`s.
    @MainActor
    public static func label(_ text: String, _ role: LabelRole, width: CGFloat? = nil) -> NSTextField {
        let l = role == .note ? NSTextField(wrappingLabelWithString: text) : NSTextField(labelWithString: text)
        switch role {
        case .panelTitle: l.font = Typography.sectionHeader.font; l.textColor = Palette.textPrimary
        case .formLabel: l.font = Typography.label.font; l.textColor = Palette.textSecondary; l.alignment = .right
        case .note: l.font = Typography.caption.font; l.textColor = Palette.textSecondary
        case .caption: l.font = Typography.caption.font; l.textColor = Palette.textSecondary
        }
        if let width {
            l.preferredMaxLayoutWidth = width
            l.frame.size.width = width
        }
        l.lineBreakMode = role == .note ? .byWordWrapping : .byTruncatingTail
        return l
    }
}
