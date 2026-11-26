import AppKit

/// The window toolbar: tool strip on the left, background toggle, and the
/// actions (Copy, Save, drag handle, More) on the right.
@MainActor final class EditorToolbar: NSObject, NSToolbarDelegate {
    let toolbar = NSToolbar(identifier: "app.shotz.editor")
    private let model: EditorModel
    private let commandMenu: NSMenu
    let dragHandle = DragHandleView(frame: .zero)
    private var toolGroup: NSToolbarItemGroup?
    private var backgroundButton: NSButton?
    var onSelectTool: ((ToolKind) -> Void)?
    var onToggleBackground: (() -> Void)?
    var onCopy: (() -> Void)?
    var onSave: (() -> Void)?

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
        backgroundButton?.state = visible ? .on : .off
    }

    private func syncTool() {
        guard let group = toolGroup, let i = ToolKind.allCases.firstIndex(of: model.toolKind) else { return }
        group.selectedIndex = i
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.toolsID, .space, Self.backgroundID, .flexibleSpace, Self.copyID, Self.saveID, Self.dragID, Self.moreID]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        toolbarDefaultItemIdentifiers(toolbar)
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        switch id {
        case Self.toolsID:
            let kinds = ToolKind.allCases
            let images = kinds.map { NSImage(systemSymbolName: $0.symbolName, accessibilityDescription: $0.title) ?? NSImage() }
            let group = NSToolbarItemGroup(itemIdentifier: id, images: images, selectionMode: .selectOne,
                                           labels: kinds.map(\.title), target: self, action: #selector(toolPicked(_:)))
            for (item, kind) in zip(group.subitems, kinds) {
                item.toolTip = "\(kind.title) (\(String(kind.key).uppercased()))"
                item.label = kind.title
            }
            group.controlRepresentation = .expanded
            group.selectedIndex = kinds.firstIndex(of: model.toolKind) ?? 0
            group.label = String(localized: "Tools")
            toolGroup = group
            return group
        case Self.backgroundID:
            let b = NSButton(image: NSImage(systemSymbolName: "square.on.square.squareshape.controlhandles",
                                            accessibilityDescription: String(localized: "Background")) ?? NSImage(),
                             target: self, action: #selector(toggleBackground))
            b.setButtonType(.pushOnPushOff)
            b.bezelStyle = .toolbar
            backgroundButton = b
            return item(id, String(localized: "Background"), "\(String(localized: "Background")) (G)", b)
        case Self.copyID:
            let b = NSButton(title: String(localized: "Copy"), image: NSImage(systemSymbolName: "doc.on.doc", accessibilityDescription: nil) ?? NSImage(),
                             target: self, action: #selector(copyPressed))
            b.bezelStyle = .toolbar
            b.imagePosition = .imageLeading
            return item(id, String(localized: "Copy"), String(localized: "Copy the finished image (⇧⌘C)"), b)
        case Self.saveID:
            let b = NSButton(title: String(localized: "Save"), image: NSImage(systemSymbolName: "square.and.arrow.down", accessibilityDescription: nil) ?? NSImage(),
                             target: self, action: #selector(savePressed))
            b.bezelStyle = .toolbar
            b.imagePosition = .imageLeading
            return item(id, String(localized: "Save"), String(localized: "Save to the export folder (⌘S)"), b)
        case Self.dragID:
            return item(id, String(localized: "Drag"), dragHandle.toolTip ?? "", dragHandle)
        case Self.moreID:
            let more = NSMenuToolbarItem(itemIdentifier: id)
            more.image = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: String(localized: "More"))
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

    @objc private func toolPicked(_ sender: NSToolbarItemGroup) {
        let kinds = ToolKind.allCases
        guard sender.selectedIndex >= 0, sender.selectedIndex < kinds.count else { return }
        onSelectTool?(kinds[sender.selectedIndex])
    }

    @objc private func toggleBackground() { onToggleBackground?() }
    @objc private func copyPressed() { onCopy?() }
    @objc private func savePressed() { onSave?() }
}
