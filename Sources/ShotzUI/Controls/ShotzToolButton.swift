import AppKit
import ShotzCore

/// A tool in the editor's tool strip: a 32-pt square, quiet at rest, and when selected a soft
/// accent-tinted square with a crisp accent edge and an accent glyph (never a solid block).
@MainActor
public final class ShotzToolButton: ShotzControlView {
    public var icon: ShotzIcon { didSet { needsDisplay = true; setAccessibilityLabel(icon.accessibilityDescription) } }

    public init(icon: ShotzIcon) {
        self.icon = icon
        super.init(frame: .zero)
        setAccessibilityRole(.radioButton)
        setAccessibilityLabel(icon.accessibilityDescription)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ShotzUI.ToolMetrics.size, height: ShotzUI.ToolMetrics.size)
    }

    public override func selectionChanged() { setAccessibilityValue(isSelected ? 1 : 0) }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let m = ShotzUI.ToolMetrics.self
        let side = min(m.size, bounds.width, bounds.height)
        let chrome = CGRect(x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side)
        let path = CGPath(roundedRect: chrome, cornerWidth: m.radius, cornerHeight: m.radius, transform: nil)
        let fills = ShotzUI.fills(for: .tool, state: state)
        drawChrome(path, fills: fills, state: state, in: ctx)
        let icon = CGRect(x: (chrome.midX - m.iconSize / 2).rounded(), y: (chrome.midY - m.iconSize / 2).rounded(), width: m.iconSize, height: m.iconSize)
        drawIcon(self.icon, in: icon, color: fills.content, ctx: ctx)
    }
}
