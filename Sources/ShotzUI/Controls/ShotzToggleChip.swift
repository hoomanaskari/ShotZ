import AppKit
import ShotzCore

/// An on/off chip for options (contrast outline, panel toggles). A capsule, outlined when off and
/// accent-tinted with an accent edge when on: visibly different from a selected tool (a square).
@MainActor
public final class ShotzToggleChip: ShotzControlView {
    public var title: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(title) } }
    public var icon: ShotzIcon? { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var isOn: Bool {
        get { isSelected }
        set { isSelected = newValue }
    }
    public var onToggle: ((Bool) -> Void)?

    public init(title: String, icon: ShotzIcon? = nil, isOn: Bool = false, size: ShotzUI.ControlSize = .compact) {
        self.title = title
        self.icon = icon
        super.init(frame: .zero)
        shotzSize = size
        isSelected = isOn
        setAccessibilityRole(.checkBox)
        setAccessibilityLabel(title)
        setAccessibilityValue(isOn ? 1 : 0)
    }

    public override var intrinsicContentSize: NSSize {
        let s = shotzSize
        // Reserve the glyph slot whether on or off so toggling never changes the width.
        let w = 2 * s.horizontalPadding + 2 + s.iconSize + s.iconLabelGap + ceil((title as NSString).size(withAttributes: [.font: s.font]).width)
        return NSSize(width: ceil(w), height: s.hitHeight)
    }

    public override func selectionChanged() { setAccessibilityValue(isSelected ? 1 : 0) }

    public override func activate(at point: CGPoint) {
        isSelected.toggle()
        onToggle?(isSelected)
        super.activate(at: point)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let s = shotzSize
        let chrome = chromeRect().insetBy(dx: 0.5, dy: 0)
        let path = CGPath(roundedRect: chrome, cornerWidth: chrome.height / 2, cornerHeight: chrome.height / 2, transform: nil)
        let fills = ShotzUI.fills(for: .chip, state: state)
        drawChrome(path, fills: fills, state: state, in: ctx)
        var x = chrome.minX + s.horizontalPadding + 1
        if let glyph = icon ?? (state.isSelected ? ShotzIcon.check : nil) {
            drawIcon(glyph, in: CGRect(x: x, y: (chrome.midY - s.iconSize / 2).rounded(), width: s.iconSize, height: s.iconSize), color: fills.content, ctx: ctx)
        } else {
            // Off without an icon: an empty ring where the check will appear.
            let r = CGRect(x: x + 2, y: (chrome.midY - s.iconSize / 2).rounded() + 2, width: s.iconSize - 4, height: s.iconSize - 4)
            ctx.setStrokeColor(fills.content.withAlphaComponent(0.7).resolved(in: effectiveAppearance).cgColor)
            ctx.setLineWidth(1.25)
            ctx.strokeEllipse(in: r.insetBy(dx: 0.6, dy: 0.6))
        }
        x += s.iconSize + s.iconLabelGap
        let tw = ceil((title as NSString).size(withAttributes: [.font: s.font]).width)
        drawText(title, font: s.font, color: fills.content, centeredIn: CGRect(x: x, y: chrome.minY, width: tw, height: chrome.height))
    }
}
