import AppKit

/// A floating panel or popover body: raised surface, 12-pt radius, hairline edge, and the overlay
/// shadow (live windows only; offline renders show the edge). Put a `ShotzFormStack` inside.
@MainActor
public final class ShotzPanel: NSView {
    /// Lay out content here (top-left origin).
    public let contentView: NSView = FlippedView()
    public var contentInsets = NSEdgeInsets(top: ShotzUI.Space.m, left: ShotzUI.Space.l, bottom: ShotzUI.Space.m, right: ShotzUI.Space.l) {
        didSet { needsLayout = true }
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.cornerRadius = ShotzUI.Radius.panel
        layer?.masksToBounds = false
        addSubview(contentView)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        contentView.frame = bounds.insetBy(dx: 0, dy: 0).inset(by: contentInsets)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let e = ShotzUI.Elevation.overlay
            layer?.shadowColor = NSColor.black.cgColor
            layer?.shadowOpacity = Float(e.opacity)
            layer?.shadowRadius = e.blur / 2
            layer?.shadowOffset = CGSize(width: 0, height: -e.offsetY)
            let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: ShotzUI.Radius.panel, yRadius: ShotzUI.Radius.panel)
            ShotzUI.Palette.surface.setFill()
            path.fill()
            ShotzUI.Palette.border.setStroke()
            path.lineWidth = 1
            path.stroke()
        }
    }
}

extension NSRect {
    func inset(by i: NSEdgeInsets) -> NSRect {
        NSRect(x: minX + i.left, y: minY + i.top, width: width - i.left - i.right, height: height - i.top - i.bottom)
    }
}

/// Rows of "label column + control" for panels and popovers (background, crop options).
/// Labels are right-aligned in secondary colour; controls share one leading edge.
@MainActor
public final class ShotzFormStack: NSView {
    public struct Row {
        public var label: String?
        public var control: NSView
        public init(_ label: String?, _ control: NSView) { self.label = label; self.control = control }
    }

    public var rows: [Row] { didSet { rebuild() } }
    public var labelWidth: CGFloat { didSet { needsLayout = true; invalidateIntrinsicContentSize() } }
    public var rowGap: CGFloat = ShotzUI.Space.s
    private var labels: [NSTextField] = []

    public init(rows: [Row], labelWidth: CGFloat = 88) {
        self.rows = rows
        self.labelWidth = labelWidth
        super.init(frame: .zero)
        rebuild()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        labels = rows.map { row in
            let l = NSTextField(labelWithString: row.label ?? "")
            l.font = ShotzUI.Typography.label.font
            l.textColor = ShotzUI.Palette.textSecondary
            l.alignment = .right
            l.lineBreakMode = .byTruncatingTail
            return l
        }
        for (l, r) in zip(labels, rows) { addSubview(l); addSubview(r.control) }
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    private func rowHeight(_ r: Row) -> CGFloat { max(r.control.intrinsicContentSize.height, 28) }

    public override var intrinsicContentSize: NSSize {
        let w = labelWidth + ShotzUI.Space.m + (rows.map { max($0.control.intrinsicContentSize.width, 0) }.max() ?? 0)
        let h = rows.reduce(0) { $0 + rowHeight($1) } + CGFloat(max(rows.count - 1, 0)) * rowGap
        return NSSize(width: ceil(w), height: ceil(h))
    }

    public override func layout() {
        super.layout()
        var y: CGFloat = 0
        for (l, r) in zip(labels, rows) {
            let h = rowHeight(r)
            let lh = ceil(l.intrinsicContentSize.height)
            l.frame = CGRect(x: 0, y: (y + (h - lh) / 2).rounded(), width: labelWidth, height: lh)
            let s = r.control.intrinsicContentSize
            let x = labelWidth + ShotzUI.Space.m
            let w = s.width > 0 ? s.width : bounds.width - x
            r.control.frame = CGRect(x: x, y: (y + (h - s.height) / 2).rounded(), width: min(w, bounds.width - x), height: s.height > 0 ? s.height : h)
            y += h + rowGap
        }
    }
}

/// A plain container with a top-left origin.
@MainActor
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
