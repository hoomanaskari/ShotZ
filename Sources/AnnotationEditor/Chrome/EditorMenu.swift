import AppKit

/// Selectors of editor commands, sent through the responder chain
/// (canvas → window → `EditorWindowController`).
@MainActor @objc protocol EditorCommands {
    func copyImage(_ sender: Any?)
    func saveImage(_ sender: Any?)
    func saveImageAs(_ sender: Any?)
    func printImage(_ sender: Any?)
    func openImageFile(_ sender: Any?)
    func newFromClipboard(_ sender: Any?)
    func duplicate(_ sender: Any?)
    func bringForward(_ sender: Any?)
    func sendBackward(_ sender: Any?)
    func bringToFront(_ sender: Any?)
    func sendToBack(_ sender: Any?)
    func zoomIn(_ sender: Any?)
    func zoomOut(_ sender: Any?)
    func zoomToFit(_ sender: Any?)
    func zoomToActualSize(_ sender: Any?)
    func toggleBackgroundPanel(_ sender: Any?)
}

/// The editor's command menu. Shotz is an agent app with no menu bar, so the
/// editor window routes key equivalents to this menu itself, and the toolbar's
/// "More" button shows it.
@MainActor enum EditorMenu {
    static func build() -> NSMenu {
        let menu = NSMenu(title: String(localized: "Editor"))
        func item(_ title: String, _ action: Selector, _ key: String, _ mods: NSEvent.ModifierFlags = .command) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
            i.keyEquivalentModifierMask = mods
            return i
        }
        func hidden(_ i: NSMenuItem) -> NSMenuItem {
            i.isHidden = true
            i.allowsKeyEquivalentWhenHidden = true
            return i
        }

        menu.addItem(item(String(localized: "Copy Image"), #selector(EditorCommands.copyImage(_:)), "c", [.command, .shift]))
        menu.addItem(item(String(localized: "Save"), #selector(EditorCommands.saveImage(_:)), "s"))
        menu.addItem(item(String(localized: "Save As…"), #selector(EditorCommands.saveImageAs(_:)), "s", [.command, .shift]))
        menu.addItem(item(String(localized: "Print…"), #selector(EditorCommands.printImage(_:)), "p"))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Add Capture from File…"), #selector(EditorCommands.openImageFile(_:)), "o"))
        menu.addItem(item(String(localized: "New from Clipboard"), #selector(EditorCommands.newFromClipboard(_:)), "n"))
        menu.addItem(.separator())

        let edit = NSMenu(title: String(localized: "Edit"))
        edit.addItem(item(String(localized: "Undo"), #selector(EditorWindow.undo(_:)), "z"))
        edit.addItem(item(String(localized: "Redo"), #selector(EditorWindow.redo(_:)), "z", [.command, .shift]))
        edit.addItem(.separator())
        edit.addItem(item(String(localized: "Cut"), #selector(NSText.cut(_:)), "x"))
        edit.addItem(item(String(localized: "Copy"), #selector(NSText.copy(_:)), "c"))
        edit.addItem(item(String(localized: "Paste"), #selector(NSText.paste(_:)), "v"))
        edit.addItem(item(String(localized: "Duplicate"), #selector(EditorCommands.duplicate(_:)), "d"))
        edit.addItem(item(String(localized: "Delete"), #selector(NSText.delete(_:)), "", []))
        edit.addItem(item(String(localized: "Select All"), #selector(NSText.selectAll(_:)), "a"))
        menu.addItem(submenu(String(localized: "Edit"), edit))

        let arrange = NSMenu(title: String(localized: "Arrange"))
        arrange.addItem(item(String(localized: "Bring Forward"), #selector(EditorCommands.bringForward(_:)), "]"))
        arrange.addItem(item(String(localized: "Send Backward"), #selector(EditorCommands.sendBackward(_:)), "["))
        arrange.addItem(item(String(localized: "Bring to Front"), #selector(EditorCommands.bringToFront(_:)), "]", [.command, .option]))
        arrange.addItem(item(String(localized: "Send to Back"), #selector(EditorCommands.sendToBack(_:)), "[", [.command, .option]))
        menu.addItem(submenu(String(localized: "Arrange"), arrange))

        let view = NSMenu(title: String(localized: "View"))
        view.addItem(item(String(localized: "Zoom In"), #selector(EditorCommands.zoomIn(_:)), "+"))
        view.addItem(hidden(item(String(localized: "Zoom In"), #selector(EditorCommands.zoomIn(_:)), "=")))
        view.addItem(item(String(localized: "Zoom Out"), #selector(EditorCommands.zoomOut(_:)), "-"))
        view.addItem(item(String(localized: "Zoom to Fit"), #selector(EditorCommands.zoomToFit(_:)), "0"))
        view.addItem(item(String(localized: "Actual Size"), #selector(EditorCommands.zoomToActualSize(_:)), "1"))
        view.addItem(.separator())
        view.addItem(item(String(localized: "Background"), #selector(EditorCommands.toggleBackgroundPanel(_:)), "", []))
        menu.addItem(submenu(String(localized: "View"), view))

        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Close"), #selector(NSWindow.performClose(_:)), "w"))
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.submenu = menu
        return i
    }
}
