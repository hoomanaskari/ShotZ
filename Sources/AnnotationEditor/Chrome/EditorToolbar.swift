import AppKit

/// The window toolbar: tool strip on the left, background toggle, and the
/// actions (Copy, Save, drag handle, More) on the right.
@MainActor final class EditorToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "app.shotz.editor")
    private let model: EditorModel
    private let commandMenu: NSMenu
    let dragHandle = DragHandleView(frame: .zero)
    private var toolStrip: GlyphSegmentedControl?
    private var backgroundToggle: GlyphSegmentedControl?
    var onSelectTool: ((ToolKind) -> Void)?
    var onToggleBackground: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

    /// Tool strip order and groups: select · drawing · text and numbers · redact and crop.
    static let toolOrder: [ToolKind] = [.select, .arrow, .line, .rectangle, .ellipse, .pen, .highlighter, .text, .counter, .redact, .crop]
    static let groupStarts: Set<Int> = [1, 7, 9]

    private static let toolsID = NSToolbarItem.Identifier("tools")
    private static let backgroundID = NSToolbarItem.Identifier("background")
    private static let copyID = NSToolbarItem.Identifier("copy")
    private static let saveID = NSToolbarItem.Identifier("save")
    private static let dragID = NSToolbarItem.Identifier("drag")
    private static let moreID = NSToolbarItem.Identifier("more")

    init(model: EditorModel, commandMenu: NSMenu) {
        self.model = model
        self.commandMenu = commandMenu
        super.init()
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        model.observe { [weak self] event in
            if event == .tool { self?.syncTool() }
        }
    }

    func setBackgroundPanelVisible(_ visible: Bool) {
        backgroundToggle?.selectedIndex = visible ? 0 : nil
    }

    private func syncTool() {
        toolStrip?.selectedIndex = Self.toolOrder.firstIndex(of: model.toolKind)
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toolsID, Self.backgroundID, .flexibleSpace, Self.dragID, Self.saveID, Self.copyID, Self.moreID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.toolsID:
            let segments = Self.toolOrder.map { kind in
                GlyphSegmentedControl.Segment(image: EditorGlyphs.image(.tool(kind), size: 20, label: kind.title), title: nil,
                                              label: kind.title, shortcut: String(kind.key).uppercased())
            }
            let strip = GlyphSegmentedControl(style: .tools, segments: segments,
                                              selected: Self.toolOrder.firstIndex(of: model.toolKind), label: String(localized: "Tools"))
            strip.groupStarts = Self.groupStarts
            strip.onSelect = { [weak self] i in self?.onSelectTool?(Self.toolOrder[i]) }
            toolStrip = strip
            return item(id, String(localized: "Tools"), String(localized: "Tools"), strip)
        case Self.backgroundID:
            let toggle = GlyphSegmentedControl(
                style: .tools,
                segments: [.init(image: EditorGlyphs.image(.background, size: 20, label: String(localized: "Background")), title: nil,
                                 label: String(localized: "Background"), shortcut: "G")],
                selected: nil, label: String(localized: "Background"))
            toggle.setAccessibilityRole(.checkBox)
            toggle.onSelect = { [weak self] _ in self?.onToggleBackground?() }
            backgroundToggle = toggle
            return item(id, String(localized: "Background"), "\(String(localized: "Background"))  G", toggle)
        case Self.copyID:
            let b = actionButton(String(localized: "Copy"), glyph: .copy, prominent: true, action: #selector(copyPressed))
            return item(id, String(localized: "Copy"), String(localized: "Copy the finished image  ⇧⌘C"), b)
        case Self.saveID:
            let b = actionButton(String(localized: "Save"), glyph: .save, prominent: false, action: #selector(savePressed))
            return item(id, String(localized: "Save"), String(localized: "Save to the export folder  ⌘S"), b)
        case Self.dragID:
            return item(id, String(localized: "Drag"), dragHandle.toolTip ?? "", dragHandle)
        case Self.moreID:
            let more = NSMenuToolbarItem(itemIdentifier: id)
            more.image = EditorGlyphs.image(.more, size: 18, label: String(localized: "More"))
            more.menu = commandMenu
            more.showsIndicator = false
            more.label = String(localized: "More")
            more.toolTip = String(localized: "More commands")
            return more
        default:
            return nil
        }
    }

    private func item(_ id: NSToolbarItem.Identifier, _ label: String, _ tip: String, _ view: NSView) -> NSToolbarItem {
        let i = NSToolbarItem(itemIdentifier: id)
        i.view = view
        i.label = label
        i.toolTip = tip
        view.setAccessibilityLabel(label)
        return i
    }

    /// Copy is the primary action (accent-filled); Save sits beside it.
    private func actionButton(_ title: String, glyph: EditorGlyph, prominent: Bool, action: Selector) -> NSButton {
        let b = NSButton(title: title, image: EditorGlyphs.image(glyph, size: 16, label: title), target: self, action: action)
        b.bezelStyle = .push
        b.controlSize = .large
        b.imagePosition = .imageLeading
        b.imageHugsTitle = true
        b.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        if prominent {
            b.bezelColor = .controlAccentColor
            b.contentTintColor = .white
        }
        b.setAccessibilityLabel(title)
        return b
    }

    @objc private func toggleBackground() { onToggleBackground?() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func savePressed() { onSave?() }
}
