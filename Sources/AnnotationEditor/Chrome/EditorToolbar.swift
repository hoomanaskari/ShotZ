import AppKit

/// The window toolbar: tool strip on the left, background toggle, and the
/// actions (Copy, Save, drag handle, More) on the right.
@MainActor final class EditorToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "app.shotz.editor")
    private let model: EditorModel
    private let commandMenu: NSMenu
    let dragHandle = DragHandleView(frame: .zero)
    /// All toolbar controls come from the chrome's control factory.
    private let controls = EditorControls()
    private var toolStrip: (any SegmentedPicker)?
    private var backgroundToggle: (any SegmentedPicker)?
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
        // Copy, the primary action, sits last on the right.
        [Self.toolsID, Self.backgroundID, .flexibleSpace, Self.moreID, Self.dragID, Self.saveID, Self.copyID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.toolsID:
            let items = Self.toolOrder.map { EditorControls.ToolItem(glyph: .tool($0), label: $0.title, shortcut: String($0.key).uppercased()) }
            let strip = controls.toolStrip(items, selected: Self.toolOrder.firstIndex(of: model.toolKind), groupStarts: Self.groupStarts,
                                           label: String(localized: "Tools")) { [weak self] i in self?.onSelectTool?(Self.toolOrder[i]) }
            toolStrip = strip
            return item(id, String(localized: "Tools"), String(localized: "Tools"), strip)
        case Self.backgroundID:
            let toggle = controls.toolbarToggle(.init(glyph: .background, label: String(localized: "Background"), shortcut: "G"),
                                                on: false) { [weak self] in self?.onToggleBackground?() }
            backgroundToggle = toggle
            return item(id, String(localized: "Background"), "\(String(localized: "Background"))  G", toggle)
        case Self.copyID:
            let b = controls.primaryButton(String(localized: "Copy"), glyph: .copy,
                                           tooltip: String(localized: "Copy the finished image  ⇧⌘C")) { [weak self] in self?.onCopy?() }
            return item(id, String(localized: "Copy"), String(localized: "Copy the finished image  ⇧⌘C"), b)
        case Self.saveID:
            let b = controls.secondaryButton(String(localized: "Save"), glyph: .save,
                                             tooltip: String(localized: "Save to the export folder  ⌘S")) { [weak self] in self?.onSave?() }
            return item(id, String(localized: "Save"), String(localized: "Save to the export folder  ⌘S"), b)
        case Self.dragID:
            return item(id, String(localized: "Drag"), dragHandle.toolTip ?? "", dragHandle)
        case Self.moreID:
            let b = controls.iconButton(.more, label: String(localized: "More commands"),
                                        tooltip: String(localized: "More commands: Save As, Print, Arrange, Zoom…")) { [weak self] button in
                self?.showCommandMenu(from: button)
            }
            return item(id, String(localized: "More"), String(localized: "More commands: Save As, Print, Arrange, Zoom…"), b)
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

    private func showCommandMenu(from button: NSButton) {
        commandMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

}
