import AppKit
import ShotzCore

/// Primary / secondary / quiet / destructive / glass buttons with text, icon + text, or icon only.
/// One primary per surface. Icon-only buttons are square and need a tooltip (`setShotzToolTip`).
@MainActor
public final class ShotzButton: ShotzControlView {
    public var title: String? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; updateAccessibility() } }
    public var icon: ShotzIcon? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; updateAccessibility() } }
    public var role: ShotzUI.ControlRole = .secondary { didSet { needsDisplay = true } }
    /// Overrides the label font (e.g. `Typography.value` for a zoom percentage).
    public var titleFont: NSFont? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Keeps paired buttons (Copy / Save) the same width.
    public var minimumWidth: CGFloat = 0 { didSet { invalidateIntrinsicContentSize() } }

    public init(title: String? = nil, icon: ShotzIcon? = nil, role: ShotzUI.ControlRole = .secondary, size: ShotzUI.ControlSize = .regular) {
        super.init(frame: .zero)
        self.title = title
        self.icon = icon
        self.role = role
        self.shotzSize = size
        setAccessibilityRole(.button)
        updateAccessibility()
    }

    private var isIconOnly: Bool { (title ?? "").isEmpty && icon != nil }

    public override var intrinsicContentSize: NSSize {
        let s = shotzSize
        if isIconOnly { return NSSize(width: s.hitHeight, height: s.hitHeight) }
        var w = 2 * s.horizontalPadding
        if icon != nil { w += s.iconSize + s.iconLabelGap }
        if let title { w += ceil((title as NSString).size(withAttributes: [.font: titleFont ?? s.font]).width) }
        // Text buttons get a little extra breathing room so short labels don't look cramped.
        return NSSize(width: max(ceil(w) + 4, minimumWidth, s.height * 2), height: s.hitHeight)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let s = shotzSize
        var chrome = chromeRect()
        if isIconOnly { chrome = CGRect(x: ((bounds.width - s.height) / 2).rounded(), y: chrome.minY, width: s.height, height: s.height) }
        let radius = role == .glass ? chrome.height / 2 : s.radius
        let path = CGPath(roundedRect: chrome, cornerWidth: radius, cornerHeight: radius, transform: nil)
        let fills = ShotzUI.fills(for: role, state: state)
        drawChrome(path, fills: fills, state: state, in: ctx)

        let font = titleFont ?? s.font
        let titleWidth = title.map { ceil(($0 as NSString).size(withAttributes: [.font: font]).width) } ?? 0
        let contentWidth = (icon != nil ? s.iconSize : 0) + (icon != nil && titleWidth > 0 ? s.iconLabelGap : 0) + titleWidth
        var x = (chrome.midX - contentWidth / 2).rounded()
        if let icon {
            let r = CGRect(x: x, y: (chrome.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize)
            drawIcon(icon, in: r, color: fills.content, ctx: ctx)
            x += s.iconSize + s.iconLabelGap
        }
        if let title, titleWidth > 0 {
            drawText(title, font: font, color: fills.content, centeredIn: CGRect(x: x, y: chrome.minY, width: titleWidth, height: chrome.height))
        }
    }

    private func updateAccessibility() {
        setAccessibilityLabel(title ?? icon?.accessibilityDescription)
    }
}
