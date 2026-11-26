import AppKit
import ShotzCore

/// Reference composition for the editor's options bar (arrow tool selected), built only from
/// ShotZ controls in a `ShotzToolbarStack`. Every control is compact (24 pt chrome, 28 pt hit):
///
///     ●●●●●●●●◎  │  [thickness ▁▂▃▄▅]  │  [arrow style ↗ ↪ ➚ ⤢ •→]  │  (✓ Outline)  │  ◐ ───●── 100 %
///
/// Order: colour, size, style, toggles, opacity: the properties in the order people change them.
/// Labels aren't needed: every control has a tooltip and an accessibility label.
@MainActor
public final class EditorOptionsBar: NSView {
    public let swatches: ShotzSwatchRow
    public let thickness = ShotzSegmentedControl.thicknessPicker(selected: 1)
    public let arrowStyle = ShotzSegmentedControl(segments: [ShotzIcon.arrowStraight, .arrowCurved, .arrowTapered, .arrowDoubleHeaded, .arrowLineWithDot].map { .init(icon: $0) },
                                                  selectedIndex: 0, size: .compact)
    public let outline = ShotzToggleChip(title: String(localized: "Outline"))
    public let opacity = ShotzSlider(value: 1, icon: .opacity, label: String(localized: "Opacity"), size: .compact)
    public let stack: ShotzToolbarStack

    public init(swatches: [ShotzSwatchRow.Swatch]) {
        self.swatches = ShotzSwatchRow(swatches: swatches, selectedIndex: 0, size: .compact)
        opacity.trackWidth = 88
        thickness.setShotzToolTip(String(localized: "Thickness"))
        arrowStyle.setShotzToolTip(String(localized: "Arrow style"), shortcut: "A")
        arrowStyle.setAccessibilityLabel(String(localized: "Arrow style"))
        outline.setShotzToolTip(String(localized: "Contrast outline"))
        opacity.setShotzToolTip(String(localized: "Opacity"))
        stack = ShotzToolbarStack(groups: [[self.swatches], [thickness], [arrowStyle], [outline], [opacity]])
        super.init(frame: .zero)
        addSubview(stack)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    /// Bar height: 40 pt (8 pt above and below the 24-pt controls' 28-pt hit area plus hairline).
    public static let height: CGFloat = 40

    public override var intrinsicContentSize: NSSize {
        NSSize(width: stack.intrinsicContentSize.width + 2 * ShotzUI.Space.m, height: Self.height)
    }

    public override func layout() {
        super.layout()
        let s = stack.intrinsicContentSize
        stack.frame = CGRect(x: ShotzUI.Space.m, y: ((bounds.height - s.height) / 2).rounded(), width: s.width, height: s.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ShotzUI.Palette.windowBackground.setFill()
            bounds.fill()
            ShotzUI.Palette.separator.setFill()
            NSRect(x: 0, y: bounds.maxY - 1, width: bounds.width, height: 1).fill()
        }
    }
}
