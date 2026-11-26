import AppKit

/// Lays out toolbar / options-bar controls in groups with the standard rhythm: `itemGap`
/// between controls in a group, `Space.m` + a hairline separator + `Space.m` between groups,
/// everything vertically centred. Use it instead of hand-placed frames so every bar shares a grid.
@MainActor
public final class ShotzToolbarStack: NSView {
    public var groups: [[NSView]] { didSet { rebuild() } }
    public var itemGap: CGFloat = ShotzUI.Space.xs { didSet { needsLayout = true; invalidateIntrinsicContentSize() } }
    public var groupGap: CGFloat = ShotzUI.Space.m { didSet { needsLayout = true; invalidateIntrinsicContentSize() } }
    public var showsSeparators = true { didSet { rebuild() } }
    private var separators: [ShotzSeparator] = []

    public init(groups: [[NSView]]) {
        self.groups = groups
        super.init(frame: .zero)
        rebuild()
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        separators = showsSeparators ? (0..<max(groups.count - 1, 0)).map { _ in ShotzSeparator() } : []
        for v in groups.flatMap({ $0 }) + separators { addSubview(v) }
        needsLayout = true
        invalidateIntrinsicContentSize()
    }

    public override var intrinsicContentSize: NSSize {
        var w: CGFloat = 0, h: CGFloat = 28
        for (gi, g) in groups.enumerated() {
            for (i, v) in g.enumerated() {
                let s = v.intrinsicContentSize
                w += max(s.width, 0) + (i > 0 ? itemGap : 0)
                h = max(h, s.height)
            }
            if gi < groups.count - 1 { w += 2 * groupGap + (showsSeparators ? 1 : 0) }
        }
        return NSSize(width: ceil(w), height: h)
    }

    public override func layout() {
        super.layout()
        var x: CGFloat = 0
        for (gi, g) in groups.enumerated() {
            for (i, v) in g.enumerated() {
                if i > 0 { x += itemGap }
                let s = v.intrinsicContentSize
                v.frame = CGRect(x: x, y: ((bounds.height - s.height) / 2).rounded(), width: s.width, height: s.height)
                x += s.width
            }
            if gi < groups.count - 1 {
                x += groupGap
                if showsSeparators {
                    separators[gi].frame = CGRect(x: x, y: 0, width: 1, height: bounds.height)
                    x += 1
                }
                x += groupGap
            }
        }
    }
}
