import AppKit
import ShotzCore

/// A pop-up / menu button: secondary chrome with an up-down chevron for choosing a value
/// (format, aspect preset), or quiet chrome with a down chevron for a menu of actions.
@MainActor
public final class ShotzPopUpButton: ShotzControlView {
    public var items: [String] { didSet { rebuildMenu(); invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var selectedIndex: Int { didSet { rebuildMenu(); needsDisplay = true; setAccessibilityValue(title) } }
    public var icon: ShotzIcon? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var role: ShotzUI.ControlRole { didSet { needsDisplay = true } }
    /// Overrides the label font (e.g. `Typography.value` for numbers like "100 %").
    public var titleFont: NSFont? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// When set, the button shows a menu of actions instead of a selection (title stays fixed).
    public var actionMenu: NSMenu?
    public var onChange: ((Int) -> Void)?
    /// The choices menu (internal: tests choose items through it, as AppKit does).
    let choiceMenu = NSMenu()

    public init(items: [String], selectedIndex: Int = 0, icon: ShotzIcon? = nil, role: ShotzUI.ControlRole = .secondary, size: ShotzUI.ControlSize = .regular) {
        self.items = items
        self.selectedIndex = min(max(selectedIndex, 0), max(items.count - 1, 0))
        self.icon = icon
        self.role = role
        super.init(frame: .zero)
        shotzSize = size
        setAccessibilityRole(.popUpButton)
        rebuildMenu()
        setAccessibilityValue(title)
    }

    public var title: String { items.indices.contains(selectedIndex) ? items[selectedIndex] : "" }
    private var chevron: ShotzIcon { role == .quiet ? .chevronDown : .chevronUpDown }
    private var labelFont: NSFont { titleFont ?? shotzSize.font }

    public override var intrinsicContentSize: NSSize {
        let s = shotzSize
        let widest = items.map { ceil(($0 as NSString).size(withAttributes: [.font: labelFont]).width) }.max() ?? 0
        var w = 2 * s.horizontalPadding + widest + s.iconLabelGap + s.iconSize - 2
        if icon != nil { w += s.iconSize + s.iconLabelGap }
        return NSSize(width: ceil(w), height: s.hitHeight)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let s = shotzSize
        let chrome = chromeRect()
        let path = CGPath(roundedRect: chrome, cornerWidth: s.radius, cornerHeight: s.radius, transform: nil)
        let fills = ShotzUI.fills(for: role, state: state)
        drawChrome(path, fills: fills, state: state, in: ctx)
        var x = chrome.minX + s.horizontalPadding
        if let icon {
            drawIcon(icon, in: CGRect(x: x, y: (chrome.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize), color: fills.content, ctx: ctx)
            x += s.iconSize + s.iconLabelGap
        }
        let attrs: [NSAttributedString.Key: Any] = [.font: labelFont, .foregroundColor: fills.content]
        let size = (title as NSString).size(withAttributes: attrs)
        (title as NSString).draw(at: CGPoint(x: x.rounded(), y: (chrome.midY - size.height / 2).rounded()), withAttributes: attrs)
        let c = s.iconSize - 2
        let secondary = state.isEnabled ? ShotzUI.Palette.textSecondary : ShotzUI.Palette.textTertiary
        drawIcon(chevron, in: CGRect(x: chrome.maxX - s.horizontalPadding - c + 2, y: (chrome.midY - c / 2).rounded(), width: c, height: c),
                 color: role == .primary ? fills.content : secondary, ctx: ctx)
    }

    private func rebuildMenu() {
        choiceMenu.removeAllItems()
        for (i, title) in items.enumerated() {
            let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            item.state = i == selectedIndex ? .on : .off
            choiceMenu.addItem(item)
        }
    }

    @objc private func choose(_ item: NSMenuItem) {
        guard item.tag != selectedIndex else { return }
        selectedIndex = item.tag
        onChange?(selectedIndex)
        sendAction(action, to: target)
    }

    public override func activate(at point: CGPoint) {
        let menu = actionMenu ?? choiceMenu
        let anchor = actionMenu == nil ? menu.item(at: selectedIndex) : nil
        isHovered = false
        menu.popUp(positioning: anchor, at: CGPoint(x: chromeRect().minX, y: actionMenu == nil ? chromeRect().minY + 1 : chromeRect().maxY + 4), in: self)
        onAction?(self)
    }
}

extension ShotzSegmentedControl {
    /// The stepped picker for thickness: five glyphs of growing weight in a segmented track.
    public static func thicknessPicker(selected: Int, size: ShotzUI.ControlSize = .compact) -> ShotzSegmentedControl {
        let c = ShotzSegmentedControl(segments: ShotzIcon.thicknessSteps.map { .init(icon: $0) }, selectedIndex: selected, size: size)
        c.setAccessibilityLabel(String(localized: "Thickness"))
        return c
    }
}
