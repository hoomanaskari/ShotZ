import AppKit
import ShotzCore

/// Reference composition for the editor's trailing title-bar area, built only from ShotZ controls.
///
///     [−][100 %][+]  │  [drag][…]  │  [⧉ Copy] [⤓ Save]
///
/// Hierarchy: Save is the single primary action, trailing (Mac convention). Copy is secondary
/// with a label and the same width as Save. Drag-out and More are quiet icon buttons with
/// tooltips. Zoom is its own leading group. Everything is 28 pt; gaps are 4 pt inside a group of
/// icon buttons, 8 pt between labelled buttons and 12 pt + separator between groups.
@MainActor
public final class EditorActionArea: NSView {
    public let zoomOutButton = ShotzButton(icon: .zoomOut, role: .quiet)
    public let zoomValueButton = ShotzButton(title: "100 %", role: .quiet)
    public let zoomInButton = ShotzButton(icon: .zoomIn, role: .quiet)
    public let dragButton = ShotzButton(icon: .dragHandle, role: .quiet)
    public let moreButton = ShotzButton(icon: .more, role: .quiet)
    public let copyButton = ShotzButton(title: String(localized: "Copy"), icon: .copy, role: .secondary)
    public let saveButton = ShotzButton(title: String(localized: "Save"), icon: .save, role: .primary)
    private let separators = [ShotzSeparator(), ShotzSeparator()]

    private var groups: [[NSView]] {
        [[zoomOutButton, zoomValueButton, zoomInButton], [dragButton, moreButton], [copyButton, saveButton]]
    }

    public override init(frame: NSRect) {
        super.init(frame: frame)
        zoomValueButton.titleFont = ShotzUI.Typography.value.font
        zoomValueButton.minimumWidth = 56
        zoomValueButton.setShotzToolTip(String(localized: "Zoom"), shortcut: "⌘0 / ⌘1")
        zoomValueButton.setAccessibilityLabel(String(localized: "Zoom level"))
        zoomOutButton.setShotzToolTip(String(localized: "Zoom out"), shortcut: "⌘−")
        zoomInButton.setShotzToolTip(String(localized: "Zoom in"), shortcut: "⌘+")
        dragButton.setShotzToolTip(String(localized: "Drag the image into another app"))
        moreButton.setShotzToolTip(String(localized: "More"))
        copyButton.setShotzToolTip(String(localized: "Copy image"), shortcut: "⇧⌘C")
        saveButton.setShotzToolTip(String(localized: "Save to export folder"), shortcut: "⌘S")
        let pair = max(copyButton.intrinsicContentSize.width, saveButton.intrinsicContentSize.width)
        copyButton.minimumWidth = pair
        saveButton.minimumWidth = pair
        for view in groups.flatMap({ $0 }) + separators { addSubview(view) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    private func gap(between a: NSView, _ b: NSView) -> CGFloat {
        (a as? ShotzButton)?.title != nil && (b as? ShotzButton)?.title != nil && a !== zoomValueButton && b !== zoomValueButton
            ? ShotzUI.Space.s : ShotzUI.Space.xs
    }

    public override var intrinsicContentSize: NSSize {
        var w: CGFloat = 0
        for (gi, group) in groups.enumerated() {
            for (i, v) in group.enumerated() {
                w += v.intrinsicContentSize.width
                if i > 0 { w += gap(between: group[i - 1], v) }
            }
            if gi < groups.count - 1 { w += 2 * ShotzUI.Space.m + 1 }
        }
        return NSSize(width: ceil(w), height: ShotzUI.ControlSize.regular.hitHeight)
    }

    public override func layout() {
        super.layout()
        var x = max(bounds.width - intrinsicContentSize.width, 0) // trailing-aligned
        let h = ShotzUI.ControlSize.regular.hitHeight
        let y = ((bounds.height - h) / 2).rounded()
        for (gi, group) in groups.enumerated() {
            for (i, v) in group.enumerated() {
                if i > 0 { x += gap(between: group[i - 1], v) }
                let w = v.intrinsicContentSize.width
                v.frame = CGRect(x: x, y: y, width: w, height: h)
                x += w
            }
            if gi < groups.count - 1 {
                x += ShotzUI.Space.m
                separators[gi].frame = CGRect(x: x, y: y, width: 1, height: h)
                x += 1 + ShotzUI.Space.m
            }
        }
    }
}
