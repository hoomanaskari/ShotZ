import AppKit
import ShotzCore

/// A segmented picker with a raised selection that slides between segments. Text or icon
/// segments (icon segments are square and need accessibility labels, which `ShotzIcon` supplies).
@MainActor
public final class ShotzSegmentedControl: ShotzControlView {
    public struct Segment: Sendable, Equatable {
        public var title: String?
        public var icon: ShotzIcon?
        public init(title: String) { self.title = title }
        public init(icon: ShotzIcon) { self.icon = icon }
        var label: String { title ?? icon?.accessibilityDescription ?? "" }
    }

    public var segments: [Segment] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; rebuildAccessibility() } }
    public private(set) var selectedIndex: Int
    /// Called with the new index when the user changes the selection.
    public var onChange: ((Int) -> Void)?
    /// Hovered segment, for hover feedback (or forced by previews).
    public var hoveredIndexOverride: Int? { didSet { needsDisplay = true } }
    private var hoveredIndex: Int? { didSet { needsDisplay = true } }

    /// Fractional segment index of the sliding thumb (animated).
    @objc public dynamic var thumbPosition: CGFloat = 0 { didSet { needsDisplay = true } }

    public init(segments: [Segment], selectedIndex: Int = 0, size: ShotzUI.ControlSize = .regular) {
        self.segments = segments
        self.selectedIndex = min(max(selectedIndex, 0), max(segments.count - 1, 0))
        super.init(frame: .zero)
        shotzSize = size
        thumbPosition = CGFloat(self.selectedIndex)
        setAccessibilityRole(.radioGroup)
        rebuildAccessibility()
    }

    public override class func defaultAnimation(forKey key: NSAnimatablePropertyKey) -> Any? {
        key == "thumbPosition" ? CABasicAnimation() : super.defaultAnimation(forKey: key)
    }

    /// Changes the selection (animated slide unless Reduce Motion is on).
    public func select(_ index: Int, animated: Bool = true) {
        let i = min(max(index, 0), segments.count - 1)
        guard i != selectedIndex || thumbPosition != CGFloat(i) else { return }
        selectedIndex = i
        if animated, ShotzUI.Motion.standard > 0 {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = ShotzUI.Motion.standard
                ctx.timingFunction = ShotzUI.Motion.move
                animator().thumbPosition = CGFloat(i)
            }
        } else {
            thumbPosition = CGFloat(i)
        }
        rebuildAccessibility()
    }

    private var isIconOnly: Bool { segments.allSatisfy { $0.title == nil } }

    private var segmentWidth: CGFloat {
        let s = shotzSize
        if isIconOnly { return s.height + 4 }
        let widest = segments.map { ceil(($0.title.map { ($0 as NSString).size(withAttributes: [.font: s.font]).width } ?? 0)) + (($0.icon != nil) ? s.iconSize + s.iconLabelGap : 0) }.max() ?? 0
        return max(widest + 2 * s.horizontalPadding, s.height * 1.6)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(segmentWidth) * CGFloat(segments.count) + 4, height: shotzSize.hitHeight)
    }

    /// Segment `i` (fractional while the thumb slides). Edges are whole points so the thumb and
    /// labels line up exactly for any width or segment count.
    private func segmentRect(_ i: CGFloat, in track: CGRect) -> CGRect {
        let inner = track.insetBy(dx: 2, dy: 2)
        let n = CGFloat(max(segments.count, 1))
        func edge(_ k: CGFloat) -> CGFloat { (inner.minX + inner.width * k / n).rounded() }
        let lo = floor(i), hi = min(lo + 1, n), f = i - lo
        let x0 = edge(lo) + (edge(hi) - edge(lo)) * f
        let x1 = edge(min(lo + 1, n)) + (edge(min(hi + 1, n)) - edge(min(lo + 1, n))) * f
        return CGRect(x: x0, y: inner.minY, width: max(x1 - x0, 0), height: inner.height)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let s = shotzSize
        let track = chromeRect()
        let a = effectiveAppearance
        let trackPath = CGPath(roundedRect: track, cornerWidth: s.radius, cornerHeight: s.radius, transform: nil)
        ctx.addPath(trackPath)
        ctx.setFillColor(ShotzUI.Palette.surfaceSunken.resolved(in: a).cgColor)
        ctx.fillPath()

        // Hover feedback on an unselected segment.
        if let h = hoveredIndexOverride ?? hoveredIndex, h != selectedIndex, state.isEnabled {
            let r = segmentRect(CGFloat(h), in: track)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: s.radius - 2, cornerHeight: s.radius - 2, transform: nil))
            ctx.setFillColor(ShotzUI.Palette.fillHover.resolved(in: a).cgColor)
            ctx.fillPath()
        }
        // The sliding thumb.
        let thumb = segmentRect(thumbPosition, in: track)
        let thumbPath = CGPath(roundedRect: thumb, cornerWidth: s.radius - 2, cornerHeight: s.radius - 2, transform: nil)
        var thumbFills = ShotzUI.ControlFills(background: ShotzUI.Palette.raised, border: ShotzUI.Palette.border, content: ShotzUI.Palette.textPrimary, raised: true)
        if !state.isEnabled { thumbFills = ShotzUI.fills(for: .secondary, state: .disabled) }
        drawChrome(thumbPath, fills: thumbFills, state: ShotzUI.ControlState(isEnabled: state.isEnabled), in: ctx)

        for (i, seg) in segments.enumerated() {
            let r = segmentRect(CGFloat(i), in: track)
            let selected = i == selectedIndex
            let color: NSColor = !state.isEnabled ? ShotzUI.Palette.textTertiary : (selected ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textSecondary)
            let tw = seg.title.map { ceil(($0 as NSString).size(withAttributes: [.font: s.font]).width) } ?? 0
            let cw = (seg.icon != nil ? s.iconSize : 0) + (seg.icon != nil && tw > 0 ? s.iconLabelGap : 0) + tw
            var x = (r.midX - cw / 2).rounded()
            if let icon = seg.icon {
                drawIcon(icon, in: CGRect(x: x, y: (r.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize), color: color, ctx: ctx)
                x += s.iconSize + s.iconLabelGap
            }
            if let title = seg.title {
                drawText(title, font: s.font, color: color, centeredIn: CGRect(x: x, y: r.minY, width: tw, height: r.height))
            }
        }
        if state.isFocused { drawFocusRing(trackPath, in: ctx) }
    }

    private func index(at p: CGPoint) -> Int? {
        let track = chromeRect()
        guard bounds.contains(p) else { return nil }
        let w = track.insetBy(dx: 2, dy: 2).width / CGFloat(max(segments.count, 1))
        return min(max(Int((p.x - track.minX - 2) / w), 0), segments.count - 1)
    }

    public override func mouseMoved(with event: NSEvent) { hoveredIndex = index(at: convert(event.locationInWindow, from: nil)) }
    public override func mouseEntered(with event: NSEvent) { super.mouseEntered(with: event); window?.acceptsMouseMovedEvents = true }
    public override func mouseExited(with event: NSEvent) { super.mouseExited(with: event); hoveredIndex = nil }

    public override func activate(at point: CGPoint) {
        guard let i = index(at: point), i != selectedIndex else { return }
        select(i)
        onChange?(i)
        super.activate(at: point)
    }

    public override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 123: if selectedIndex > 0 { select(selectedIndex - 1); onChange?(selectedIndex); sendAction(action, to: target) }
        case 124: if selectedIndex < segments.count - 1 { select(selectedIndex + 1); onChange?(selectedIndex); sendAction(action, to: target) }
        default: super.keyDown(with: event)
        }
    }

    private func rebuildAccessibility() {
        setAccessibilityValue(segments.indices.contains(selectedIndex) ? segments[selectedIndex].label : nil)
        setAccessibilityChildren(segments.enumerated().map { i, seg in
            let e = NSAccessibilityElement()
            e.setAccessibilityRole(.radioButton)
            e.setAccessibilityLabel(seg.label)
            e.setAccessibilityValue(i == selectedIndex ? 1 : 0)
            e.setAccessibilityParent(self)
            return e
        })
    }
}
