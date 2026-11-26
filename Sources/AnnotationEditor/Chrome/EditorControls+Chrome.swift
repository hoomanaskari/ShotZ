import AppKit
import ShotzCore
import ShotzUI

/// A control whose selection the chrome sets from outside (tool strip, toggles).
@MainActor protocol SegmentedPicker: NSView {
    var selectedIndex: Int? { get set }
}

/// Toolbar compositions built only from ShotzUI controls.
extension EditorControls {
    struct ToolItem {
        var glyph: EditorGlyph
        var label: String
        var shortcut: String
    }

    /// The tool strip: ShotzToolButtons, groups split by ShotzSeparators.
    func toolStrip(_ items: [ToolItem], selected: Int?, groupStarts: Set<Int>, label: String,
                   _ onSelect: @escaping (Int) -> Void) -> any SegmentedPicker {
        ToolStripView(items: items, selected: selected, groupStarts: groupStarts, label: label, onSelect: onSelect)
    }

    /// An on/off panel switch in the toolbar: a toggle chip (a capsule), never a selected tool.
    func toolbarToggle(_ item: ToolItem, on: Bool, _ onToggle: @escaping () -> Void) -> any SegmentedPicker {
        let chip = ToolbarToggleChip(title: item.label, icon: EditorGlyphs.shotzIcon(item.glyph), isOn: on, size: .regular)
        chip.chip.setShotzToolTip(item.label, shortcut: item.shortcut)
        chip.onToggle = { _ in onToggle() }
        return chip
    }
}

/// The background toggle as a picker (on = index 0).
@MainActor final class ToolbarToggleChip: NSView, SegmentedPicker {
    // A thin adapter: ShotzToggleChip is final, so wrap it.
    let chip: ShotzToggleChip
    var onToggle: ((Bool) -> Void)? {
        get { chip.onToggle }
        set { chip.onToggle = newValue }
    }

    init(title: String, icon: ShotzIcon?, isOn: Bool, size: ShotzUI.ControlSize) {
        chip = ShotzToggleChip(title: title, icon: icon, isOn: isOn, size: size)
        super.init(frame: .zero)
        chip.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chip)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: leadingAnchor), chip.trailingAnchor.constraint(equalTo: trailingAnchor),
            chip.topAnchor.constraint(equalTo: topAnchor), chip.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var selectedIndex: Int? {
        get { chip.isOn ? 0 : nil }
        set { chip.isOn = newValue != nil }
    }
}

/// ShotzToolButtons in groups, one selected (a radio group for VoiceOver).
@MainActor final class ToolStripView: NSView, SegmentedPicker {
    private var buttons: [ShotzToolButton] = []
    private let stack = NSStackView()

    init(items: [EditorControls.ToolItem], selected: Int?, groupStarts: Set<Int>, label: String, onSelect: @escaping (Int) -> Void) {
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = ShotzUI.ToolMetrics.gap
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor), stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        for (i, item) in items.enumerated() {
            if groupStarts.contains(i) {
                let sep = EditorControls.separator(length: 20)
                stack.addArrangedSubview(sep)
                stack.setCustomSpacing(ShotzUI.Space.s, after: stack.arrangedSubviews[stack.arrangedSubviews.count - 2])
                stack.setCustomSpacing(ShotzUI.Space.s, after: sep)
            }
            guard let icon = EditorGlyphs.shotzIcon(item.glyph) else { continue }
            let b = ShotzToolButton(icon: icon)
            b.setAccessibilityLabel(item.label)
            b.setShotzToolTip(item.label, shortcut: item.shortcut)
            b.isSelected = i == selected
            b.onAction = { [weak self] _ in
                self?.selectedIndex = i
                onSelect(i)
            }
            buttons.append(b)
            stack.addArrangedSubview(b)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    var selectedIndex: Int? {
        get { buttons.firstIndex { $0.isSelected } }
        set { for (i, b) in buttons.enumerated() { b.isSelected = i == newValue } }
    }
}

/// The editor's action bar, under the canvas (ShotzUI's `EditorActionArea` hierarchy):
///
///     [−][100 %][+]                      [drag][…]  │  [Copy] [Save]  [Done]
///
/// Done is the single primary action (closes the window: "done, back to the stack").
/// Copy and Save are labelled secondaries of equal width. Drag-out and More are quiet icon
/// buttons. Zoom is its own group at the leading edge. All 28 pt; 4 pt between icon buttons,
/// 8 pt between labelled buttons, 12 pt and a separator between groups.
@MainActor final class EditorActionBar: NSView {
    let zoomOut: ShotzButton
    let zoomValue: ShotzButton
    let zoomIn: ShotzButton
    let drag: DragHandleView
    let more: ShotzButton
    let copy: ShotzButton
    let save: ShotzButton
    let done: ShotzButton
    private let separator = ShotzSeparator()

    private var zoomGroup: [NSView] { [zoomOut, zoomValue, zoomIn] }
    private var trailingGroups: [[NSView]] { [[drag, more], [copy, save, done]] }

    init(controls: EditorControls, drag: DragHandleView, onZoomOut: @escaping () -> Void, onZoomIn: @escaping () -> Void,
         onZoomMenu: @escaping (ShotzButton) -> Void, onMore: @escaping (ShotzButton) -> Void,
         onCopy: @escaping () -> Void, onSave: @escaping () -> Void, onDone: @escaping () -> Void) {
        zoomOut = controls.iconButton(.zoomOut, label: String(localized: "Zoom out"), tooltip: String(localized: "Zoom out"), shortcut: "⌘−") { _ in onZoomOut() }
        zoomIn = controls.iconButton(.zoomIn, label: String(localized: "Zoom in"), tooltip: String(localized: "Zoom in"), shortcut: "⌘+") { _ in onZoomIn() }
        zoomValue = ShotzButton(title: "100 %", role: .quiet, size: EditorControls.size)
        zoomValue.titleFont = ShotzUI.Typography.value.font
        zoomValue.minimumWidth = 56
        zoomValue.setAccessibilityLabel(String(localized: "Zoom level"))
        zoomValue.setShotzToolTip(String(localized: "Zoom: fit or actual size"), shortcut: "⌘0 / ⌘1")
        zoomValue.onAction = { b in
            guard let b = b as? ShotzButton else { return }
            onZoomMenu(b)
        }
        self.drag = drag
        more = controls.iconButton(.more, label: String(localized: "More commands"),
                                   tooltip: String(localized: "More: Save As, Print, Arrange…")) { b in onMore(b) }
        copy = controls.secondaryButton(String(localized: "Copy"), glyph: .copy, tooltip: String(localized: "Copy image"), shortcut: "⇧⌘C", onCopy)
        save = controls.secondaryButton(String(localized: "Save"), glyph: .save, tooltip: String(localized: "Save to the export folder"), shortcut: "⌘S", onSave)
        done = controls.primaryButton(String(localized: "Done"), tooltip: String(localized: "Done: close and return the capture to the stack"),
                                      shortcut: "⌘W", onDone)
        super.init(frame: .zero)
        let pair = max(copy.intrinsicContentSize.width, save.intrinsicContentSize.width)
        copy.minimumWidth = pair
        save.minimumWidth = pair
        for view in zoomGroup + trailingGroups.flatMap({ $0 }) + [separator] { addSubview(view) }
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setZoomTitle(_ title: String) {
        zoomValue.title = title
    }

    private func isLabelled(_ v: NSView) -> Bool { v === copy || v === save || v === done }

    private func gap(_ a: NSView, _ b: NSView) -> CGFloat {
        isLabelled(a) && isLabelled(b) ? ShotzUI.Space.s : ShotzUI.Space.xs
    }

    private func width(_ group: [NSView]) -> CGFloat {
        var w: CGFloat = 0
        for (i, v) in group.enumerated() {
            w += v.intrinsicContentSize.width
            if i > 0 { w += gap(group[i - 1], v) }
        }
        return w
    }

    override var intrinsicContentSize: NSSize {
        let trailing = trailingGroups.map(width).reduce(0, +) + 2 * ShotzUI.Space.m + 1
        return NSSize(width: ceil(width(zoomGroup) + ShotzUI.Space.xl + trailing), height: EditorControls.size.hitHeight)
    }

    override func layout() {
        super.layout()
        let h = EditorControls.size.hitHeight
        let y = ((bounds.height - h) / 2).rounded()
        func place(_ group: [NSView], from start: CGFloat) -> CGFloat {
            var x = start
            for (i, v) in group.enumerated() {
                if i > 0 { x += gap(group[i - 1], v) }
                let w = v.intrinsicContentSize.width
                v.frame = CGRect(x: x, y: y, width: w, height: h)
                x += w
            }
            return x
        }
        _ = place(zoomGroup, from: 0)
        let groups = trailingGroups
        var x = bounds.width - (groups.map(width).reduce(0, +) + 2 * ShotzUI.Space.m + 1)
        x = place(groups[0], from: x)
        x += ShotzUI.Space.m
        separator.frame = CGRect(x: x, y: y + 4, width: 1, height: h - 8)
        x += 1 + ShotzUI.Space.m
        _ = place(groups[1], from: x)
    }
}
