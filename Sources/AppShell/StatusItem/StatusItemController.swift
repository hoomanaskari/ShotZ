import AppKit
import ShotzCore

/// Menu-bar status item and its menu (SPEC §1).
@MainActor public final class StatusItemController: NSObject, NSMenuDelegate {
    public var onCapture: ((CaptureMode) -> Void)?
    public var onOpenLastInEditor: (() -> Void)?
    public var onSelectHistoryItem: ((CaptureResult) -> Void)?
    public var onOpenSettings: (() -> Void)?
    /// Called when the menu opens so the owner can refresh history.
    public var onMenuWillOpen: (() -> Void)?

    private let statusItem: NSStatusItem
    private let hotkeys: HotkeyCenter
    private let historyMenu = NSMenu(title: String(localized: "Capture History"))
    private var history: [CaptureResult] = []

    public init(hotkeys: HotkeyCenter) {
        self.hotkeys = hotkeys
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "camera.viewfinder", accessibilityDescription: "Shotz")
            button.toolTip = "Shotz"
        }
        statusItem.menu = buildMenu()
        updateHistory([])
    }

    public var isVisible: Bool {
        get { statusItem.isVisible }
        set { statusItem.isVisible = newValue }
    }

    /// Replaces the history submenu (last 10).
    public func updateHistory(_ items: [CaptureResult]) {
        history = Array(items.prefix(10))
        historyMenu.removeAllItems()
        if history.isEmpty {
            let empty = NSMenuItem(title: String(localized: "No Captures Yet"), action: nil, keyEquivalent: "")
            empty.isEnabled = false
            historyMenu.addItem(empty)
        }
        for (i, capture) in history.enumerated() {
            let item = NSMenuItem(title: capture.displayName, action: #selector(historyItem(_:)), keyEquivalent: "")
            item.target = self
            item.tag = i
            historyMenu.addItem(item)
        }
    }

    /// Re-reads shortcut labels (after settings or hotkey changes).
    public func refreshShortcuts() {
        statusItem.menu = buildMenu()
    }

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self
        menu.addItem(captureItem(String(localized: "Capture Area"), .area, action: .captureArea))
        menu.addItem(captureItem(String(localized: "Capture Window"), .window, action: .captureWindow))
        menu.addItem(captureItem(String(localized: "Capture Fullscreen"), .fullscreen, action: .captureFullscreen))
        menu.addItem(captureItem(String(localized: "All-in-One"), .allInOne, action: .captureAllInOne))
        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: String(localized: "Capture History"), action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        menu.addItem(historyItem)
        menu.addItem(item(String(localized: "Open Last Capture in Editor"), #selector(openLast)))
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ","))
        menu.addItem(item(String(localized: "Quit Shotz"), #selector(quit), key: "q"))
        return menu
    }

    private func captureItem(_ title: String, _ mode: CaptureMode, action: HotkeyAction) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(capture(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = action.rawValue
        if let combo = hotkeys.binding(for: action) {
            item.keyEquivalent = KeyEquivalent.character(for: combo.keyCode)
            item.keyEquivalentModifierMask = KeyEquivalent.flags(for: combo.modifiers)
        }
        return item
    }

    private func item(_ title: String, _ selector: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        return item
    }

    public func menuWillOpen(_ menu: NSMenu) {
        onMenuWillOpen?()
    }

    @objc private func capture(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = HotkeyAction(rawValue: raw)?.captureMode else { return }
        onCapture?(mode)
    }

    @objc private func historyItem(_ sender: NSMenuItem) {
        guard history.indices.contains(sender.tag) else { return }
        onSelectHistoryItem?(history[sender.tag])
    }

    @objc private func openLast() { onOpenLastInEditor?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
