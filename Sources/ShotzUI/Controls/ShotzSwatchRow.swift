import AppKit
import ShotzCore

/// A row of colour swatches with a neutral selection ring, plus an optional custom-colour well
/// (a hue ring around the current custom colour). Arrow keys move the selection.
@MainActor
public final class ShotzSwatchRow: ShotzControlView {
    public struct Swatch {
        public var color: NSColor
        public var name: String
        public init(_ color: NSColor, name: String) { self.color = color; self.name = name }
    }

    public var swatches: [Swatch] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; rebuildAccessibility() } }
    /// Index into `swatches`, or `swatches.count` for the custom well, or nil for none.
    public var selectedIndex: Int? { didSet { needsDisplay = true; rebuildAccessibility() } }
    public var showsCustomWell = true { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// The colour shown inside the custom well (nil shows a plus).
    public var customColor: NSColor? { didSet { needsDisplay = true } }
    /// Called with a swatch index, or `swatches.count` when the custom well is clicked.
    public var onSelect: ((Int) -> Void)?
    public var hoveredIndexOverride: Int? { didSet { needsDisplay = true } }
    private var hoveredIndex: Int? { didSet { needsDisplay = true } }

    /// Swatch diameter and cell pitch.
    private var diameter: CGFloat { shotzSize == .compact ? 14 : 16 }
    private var pitch: CGFloat { 28 }

    public init(swatches: [Swatch], selectedIndex: Int? = 0, size: ShotzUI.ControlSize = .regular) {
        self.swatches = swatches
        self.selectedIndex = selectedIndex
        super.init(frame: .zero)
        shotzSize = size
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(String(localized: "Colour"))
        rebuildAccessibility()
    }

    private var count: Int { swatches.count + (showsCustomWell ? 1 : 0) }

    public override var intrinsicContentSize: NSSize { NSSize(width: pitch * CGFloat(count), height: shotzSize.hitHeight) }

    private func cellRect(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i) * pitch, y: ((bounds.height - pitch) / 2).rounded(), width: pitch, height: pitch)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let a = effectiveAppearance
        let d = diameter
        ctx.saveGState()
        defer { ctx.restoreGState() }
        if !state.isEnabled { ctx.setAlpha(0.4) }
        for i in 0..<count {
            let c = cellRect(i)
            let circle = CGRect(x: c.midX - d / 2, y: c.midY - d / 2, width: d, height: d)
            let hovered = (hoveredIndexOverride ?? hoveredIndex) == i && state.isEnabled
            if i < swatches.count {
                ctx.setFillColor(swatches[i].color.resolved(in: a).cgColor)
                ctx.fillEllipse(in: circle)
                // Hairline so white on white and black on black stay visible.
                ctx.setStrokeColor(ShotzUI.Palette.swatchEdge.resolved(in: a).cgColor)
                ctx.setLineWidth(1)
                ctx.strokeEllipse(in: circle.insetBy(dx: 0.5, dy: 0.5))
            } else {
                drawCustomWell(in: circle, ctx: ctx)
            }
            let ringRect = circle.insetBy(dx: -4, dy: -4)
            if selectedIndex == i {
                ctx.setStrokeColor(ShotzUI.Palette.textPrimary.resolved(in: a).cgColor)
                ctx.setLineWidth(2)
                ctx.strokeEllipse(in: ringRect.insetBy(dx: 1, dy: 1))
            } else if hovered {
                ctx.setStrokeColor(ShotzUI.Palette.textTertiary.resolved(in: a).cgColor)
                ctx.setLineWidth(1.5)
                ctx.strokeEllipse(in: ringRect.insetBy(dx: 0.75, dy: 0.75))
            }
            if state.isFocused, selectedIndex == i || (selectedIndex == nil && i == 0) {
                drawFocusRing(CGPath(ellipseIn: ringRect.insetBy(dx: -1, dy: -1), transform: nil), in: ctx)
            }
        }
    }

    private func drawCustomWell(in circle: CGRect, ctx: CGContext) {
        let a = effectiveAppearance
        // Hue ring: short arcs stepping through the hue circle.
        let center = CGPoint(x: circle.midX, y: circle.midY), radius = circle.width / 2 - 1.5
        let steps = 48
        ctx.saveGState()
        ctx.setLineWidth(3)
        for i in 0..<steps {
            let a0 = -CGFloat.pi / 2 + CGFloat(i) / CGFloat(steps) * 2 * .pi
            let a1 = a0 + 2 * .pi / CGFloat(steps) + 0.02
            ctx.setStrokeColor(NSColor(hue: CGFloat(i) / CGFloat(steps), saturation: 0.72, brightness: 0.95, alpha: 1).cgColor)
            ctx.addArc(center: center, radius: radius, startAngle: a0, endAngle: a1, clockwise: false)
            ctx.strokePath()
        }
        ctx.restoreGState()
        let inner = circle.insetBy(dx: 4.5, dy: 4.5)
        if let custom = customColor {
            ctx.setFillColor(custom.resolved(in: a).cgColor)
            ctx.fillEllipse(in: inner)
        } else {
            drawIcon(.plus, in: inner.insetBy(dx: -1.5, dy: -1.5), color: ShotzUI.Palette.textSecondary, ctx: ctx)
        }
    }

    private func index(at p: CGPoint) -> Int? {
        guard bounds.contains(p) else { return nil }
        let i = Int(p.x / pitch)
        return i >= 0 && i < count ? i : nil
    }

    public override func mouseMoved(with event: NSEvent) { hoveredIndex = index(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); window?.acceptsMouseMovedEvents = true }
    public override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); hoveredIndex = nil }

    public override func activate(at point: CGPoint) {
        guard let i = index(at: point) else { return }
        choose(i)
    }

    private func choose(_ i: Int) {
        if i < swatches.count || customColor != nil { selectedIndex = i }
        onSelect?(i)
        sendAction(action, to: target)
        onAction?(self)
    }

    public override func keyDown(with event: NSEvent) {
        let current = selectedIndex ?? 0
        switch event.keyCode {
        case 123: choose(max(current - 1, 0))
        case 124: choose(min(current + 1, swatches.count - 1))
        default: super.keyDown(with: event)
        }
    }

    private func rebuildAccessibility() {
        setAccessibilityChildren((0..<count).map { i in
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.radioButton)
            e.setAccessibilityLabel(i < swatches.count ? swatches[i].name : String(localized: "Custom colour"))
            e.setAccessibilityValue(selectedIndex == i ? 1 : 0)
            e.setAccessibilityParent(self)
            return e
        })
    }
}
