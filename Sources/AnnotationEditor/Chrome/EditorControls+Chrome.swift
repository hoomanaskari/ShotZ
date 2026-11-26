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
        let chip = ToolbarToggleChip(title: item.label, icon: EditorGlyphs.shotzIcon(item.glyph), isOn: on, size: EditorControls.actionSize)
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

/// ShotzToolButtons in groups (a ShotzToolbarStack), one selected (a radio group for VoiceOver).
@MainActor final class ToolStripView: NSView, SegmentedPicker {
    private var buttons: [ShotzToolButton] = []
    private let stack: ShotzToolbarStack

    init(items: [EditorControls.ToolItem], selected: Int?, groupStarts: Set<Int>, label: String, onSelect: @escaping (Int) -> Void) {
        var groups: [[NSView]] = [[]]
        var made: [ShotzToolButton] = []
        for (i, item) in items.enumerated() {
            if groupStarts.contains(i), !(groups.last?.isEmpty ?? true) { groups.append([]) }
            guard let icon = EditorGlyphs.shotzIcon(item.glyph) else { continue }
            let b = ShotzToolButton(icon: icon)
            b.setAccessibilityLabel(item.label)
            b.setShotzToolTip(item.label, shortcut: item.shortcut)
            b.isSelected = i == selected
            made.append(b)
            groups[groups.count - 1].append(b)
        }
        stack = ShotzToolbarStack(groups: groups)
        stack.itemGap = ShotzUI.ToolMetrics.gap
        stack.groupGap = ShotzUI.Space.s
        buttons = made
        super.init(frame: .zero)
        for (i, b) in made.enumerated() {
            b.onAction = { [weak self] _ in
                self?.selectedIndex = i
                onSelect(i)
            }
        }
        addSubview(stack)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { stack.intrinsicContentSize }
    override func layout() {
        super.layout()
        stack.frame = bounds
    }

    var selectedIndex: Int? {
        get { buttons.firstIndex { $0.isSelected } }
        set { for (i, b) in buttons.enumerated() { b.isSelected = i == newValue } }
    }
}

/// The editor's action bar, under the canvas (ShotzUI's `EditorActionArea` hierarchy):
///
///     [−][100 % ⌄][+]                    [▭ ⠿][…]  │  [Copy] [Save]  [Done]
///
/// Done is the single primary action (closes the window: "done, back to the stack").
/// Copy and Save are labelled secondaries of equal width. Drag-out and More are quiet.
/// Zoom is its own group at the leading edge; its value is a quiet pop-up of zoom levels.
/// Regular (28 pt) controls in ShotzToolbarStacks: 4 pt between icon buttons, 8 pt between
/// labelled buttons, 12 pt and a separator between groups.
@MainActor final class EditorActionBar: NSView {
    let zoomOut: ShotzButton
    let zoomValue: ShotzPopUpButton
    let zoomIn: ShotzButton
    let drag: DragHandleView
    let more: ShotzButton
    let copy: ShotzButton
    let save: ShotzButton
    let done: ShotzButton
    private let leading: ShotzToolbarStack
    private let trailing: ShotzToolbarStack

    init(controls: EditorControls, drag: DragHandleView, zoomMenu: NSMenu, onZoomOut: @escaping () -> Void, onZoomIn: @escaping () -> Void,
         onMore: @escaping (ShotzButton) -> Void, onCopy: @escaping () -> Void, onSave: @escaping () -> Void, onDone: @escaping () -> Void) {
        let size = EditorControls.actionSize
        zoomOut = controls.iconButton(.zoomOut, label: String(localized: "Zoom out"), tooltip: String(localized: "Zoom out"), shortcut: "⌘−", size: size) { _ in onZoomOut() }
        zoomIn = controls.iconButton(.zoomIn, label: String(localized: "Zoom in"), tooltip: String(localized: "Zoom in"), shortcut: "⌘+", size: size) { _ in onZoomIn() }
        zoomValue = controls.menuButton(title: "100 %", glyph: nil, menu: zoomMenu, label: String(localized: "Zoom level"),
                                        tooltip: String(localized: "Zoom: fit, actual size or a preset"), shortcut: "⌘0 / ⌘1", size: size)
        zoomValue.titleFont = ShotzUI.Typography.value.font
        zoomValue.items = ["1600 %"] // reserve the widest value so the bar doesn't shift
        let reserved = zoomValue.intrinsicContentSize.width
        zoomValue.items = ["100 %"]
        self.drag = drag
        more = controls.iconButton(.more, label: String(localized: "More commands"),
                                   tooltip: String(localized: "More: Save As, Print, Arrange…"), size: size) { b in onMore(b) }
        copy = controls.secondaryButton(String(localized: "Copy"), glyph: .copy, tooltip: String(localized: "Copy image"), shortcut: "⇧⌘C", size: size, onCopy)
        save = controls.secondaryButton(String(localized: "Save"), glyph: .save, tooltip: String(localized: "Save to the export folder"), shortcut: "⌘S", size: size, onSave)
        done = controls.primaryButton(String(localized: "Done"), tooltip: String(localized: "Done: close and return the capture to the stack"),
                                      shortcut: "⌘W", size: size, onDone)
        let pair = max(copy.intrinsicContentSize.width, save.intrinsicContentSize.width)
        copy.minimumWidth = pair
        save.minimumWidth = pair
        let zoomValueBox = FixedWidth(zoomValue, width: reserved)
        leading = ShotzToolbarStack(groups: [[zoomOut, zoomValueBox, zoomIn]])
        leading.showsSeparators = false
        let labelled = ShotzToolbarStack(groups: [[copy, save, done]])
        labelled.itemGap = ShotzUI.Space.s
        labelled.showsSeparators = false
        trailing = ShotzToolbarStack(groups: [[drag, more], [labelled]])
        super.init(frame: .zero)
        addSubview(leading)
        addSubview(trailing)
        setAccessibilityElement(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }

    func setZoomTitle(_ title: String) {
        zoomValue.items = [title]
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: ceil(leading.intrinsicContentSize.width + ShotzUI.Space.xl + trailing.intrinsicContentSize.width),
               height: EditorControls.actionSize.hitHeight)
    }

    override func layout() {
        super.layout()
        let l = leading.intrinsicContentSize, t = trailing.intrinsicContentSize
        leading.frame = CGRect(x: 0, y: ((bounds.height - l.height) / 2).rounded(), width: l.width, height: l.height)
        trailing.frame = CGRect(x: bounds.width - t.width, y: ((bounds.height - t.height) / 2).rounded(), width: t.width, height: t.height)
    }
}

/// Holds a control at a fixed width (a value pop-up that must not resize as its value changes).
@MainActor final class FixedWidth: NSView {
    let content: NSView
    private let width: CGFloat
    init(_ content: NSView, width: CGFloat) {
        self.content = content
        self.width = width
        super.init(frame: .zero)
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { NSSize(width: width, height: content.intrinsicContentSize.height) }
    override func layout() {
        super.layout()
        let w = min(content.intrinsicContentSize.width, bounds.width)
        content.frame = CGRect(x: 0, y: 0, width: w, height: bounds.height)
    }
}
