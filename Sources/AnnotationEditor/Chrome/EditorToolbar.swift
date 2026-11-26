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
    private(set) var actionBar: EditorActionBar?
    var onSelectTool: ((ToolKind) -> Void)?
    var onToggleBackground: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?
    var onDone: (() -> Void)?
    var onZoomIn: (() -> Void)?
    var onZoomOut: (() -> Void)?

    /// Tool strip order and groups: select | shapes | text and numbers | redact and crop.
    static let toolOrder: [ToolKind] = [.select, .arrow, .line, .rectangle, .ellipse, .pen, .highlighter, .text, .counter, .redact, .crop]
    static let groupStarts: Set<Int> = [1, 7, 9]

    private static let toolsID = NSToolbarItem.Identifier("tools")
    private static let backgroundID = NSToolbarItem.Identifier("background")

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
        [Self.toolsID, Self.backgroundID]
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
            return item(id, String(localized: "Tools"), strip)
        case Self.backgroundID:
            let toggle = controls.toolbarToggle(.init(glyph: .background, label: String(localized: "Background"), shortcut: "G"),
                                                on: false) { [weak self] in self?.onToggleBackground?() }
            backgroundToggle = toggle
            return item(id, String(localized: "Background"), toggle)
        default:
            return nil
        }
    }

    /// The action area (it lives in the title row, trailing, where there is room for it).
    func makeActionBar(zoomMenu: NSMenu) -> EditorActionBar {
        if let actionBar { return actionBar }
        let bar = EditorActionBar(
            controls: controls, drag: dragHandle, zoomMenu: zoomMenu,
            onZoomOut: { [weak self] in self?.onZoomOut?() },
            onZoomIn: { [weak self] in self?.onZoomIn?() },
            onMore: { [weak self] b in self?.showCommandMenu(from: b) },
            onCopy: { [weak self] in self?.onCopy?() },
            onSave: { [weak self] in self?.onSave?() },
            onDone: { [weak self] in self?.onDone?() }
        )
        actionBar = bar
        return bar
    }

    private func item(_ id: NSToolbarItem.Identifier, _ label: String, _ view: NSView) -> NSToolbarItem {
        let i = NSToolbarItem(itemIdentifier: id)
        i.view = view
        i.label = label
        return i
    }

    private func showCommandMenu(from view: NSView) {
        commandMenu.popUp(positioning: nil, at: NSPoint(x: 0, y: view.bounds.height + 4), in: view)
    }
}
