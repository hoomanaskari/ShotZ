import AppKit
import SwiftUI

/// A folder chooser in the system's own style: an `NSPopUpButton` whose first
/// item is the folder (16 pt Finder icon and name), followed by actions.
struct FolderPopUp: NSViewRepresentable {
    let folder: URL
    let canReveal: Bool
    let showsUseDesktop: Bool
    let onChoose: () -> Void
    let onReveal: () -> Void
    let onUseDesktop: () -> Void

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.target = context.coordinator
        button.action = #selector(Coordinator.selected(_:))
        button.setAccessibilityLabel(String(localized: "Export folder"))
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        button.removeAllItems()
        let path = folder.path(percentEncoded: false)
        let current = NSMenuItem(title: FileManager.default.displayName(atPath: path), action: nil, keyEquivalent: "")
        let icon = NSWorkspace.shared.icon(forFile: path)
        icon.size = NSSize(width: 16, height: 16)
        current.image = icon
        current.toolTip = path
        button.menu?.addItem(current)
        button.menu?.addItem(.separator())
        add(String(localized: "Other…"), tag: 1, to: button)
        add(String(localized: "Show in Finder"), tag: 2, to: button).isEnabled = canReveal
        if showsUseDesktop { add(String(localized: "Use Desktop"), tag: 3, to: button) }
        button.autoenablesItems = false
        button.selectItem(at: 0)
        button.sizeToFit()
    }

    @discardableResult
    private func add(_ title: String, tag: Int, to button: NSPopUpButton) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.tag = tag
        button.menu?.addItem(item)
        return item
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    @MainActor final class Coordinator: NSObject {
        var parent: FolderPopUp
        init(parent: FolderPopUp) { self.parent = parent }

        @objc func selected(_ sender: NSPopUpButton) {
            let tag = sender.selectedItem?.tag ?? 0
            sender.selectItem(at: 0)   // the pop-up always shows the folder
            switch tag {
            case 1: parent.onChoose()
            case 2: parent.onReveal()
            case 3: parent.onUseDesktop()
            default: break
            }
        }
    }
}
