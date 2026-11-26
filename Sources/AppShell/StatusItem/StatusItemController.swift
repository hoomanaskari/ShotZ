import AppKit
import ShotzCore

/// Menu-bar status item and its menu (SPEC §1). The menu is rebuilt each
/// time it opens, so shortcut labels and enabled states are always current.
@MainActor public final class StatusItemController: NSObject, NSMenuDelegate {
    public var onCapture: ((CaptureMode) -> Void)?
    public var onOpenLastInEditor: (() -> Void)?
    public var onRestoreLastClosed: (() -> Void)?
    public var onSelectHistoryItem: ((CaptureResult) -> Void)?
    public var onOpenSettings: (() -> Void)?
    /// Called when the menu opens so the owner can refresh history.
    public var onMenuWillOpen: (() -> Void)?
    /// Software updates: "Check for Updates…" appears only when they are available.
    public var updates: SoftwareUpdates?
    /// Whether "Restore Last Closed Card" is available right now.
    public var canRestoreLastClosed: () -> Bool = { false }

    private var statusItem: NSStatusItem?
    private let hotkeys: HotkeyCenter
    private let menu = NSMenu()
    private let historyMenu = NSMenu(title: String(localized: "Capture History"))
    private var history: [CaptureResult] = []
    private let thumbnails = HistoryThumbnails()
    static let historyLimit = 10

    public init(hotkeys: HotkeyCenter) {
        self.hotkeys = hotkeys
        super.init()
        menu.delegate = self
        menu.autoenablesItems = false
        rebuildMenu()
        rebuildHistoryMenu()
    }

    /// Showing creates the status item; hiding removes it from the menu bar
    /// entirely (not just a zero-width slot).
    public var isVisible: Bool {
        get { statusItem != nil }
        set {
            guard newValue != isVisible else { return }
            if newValue {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                // Position/visibility are kept per app variant (own defaults domain).
                item.autosaveName = "ShotzStatusItem"
                item.button?.image = StatusItemIcon.make(variant: .current)
                item.button?.toolTip = AppVariant.current.displayName
                item.button?.setAccessibilityLabel(AppVariant.current.displayName)
                item.menu = menu
                statusItem = item
            } else if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        }
    }

    /// For `--debug-snapshot-ui` only: the menu as text and the button view.
    public var debugMenuDescription: String {
        menuNeedsUpdate(menu)
        func describe(_ menu: NSMenu, indent: String) -> [String] {
            menu.items.flatMap { item -> [String] in
                if item.isSeparatorItem { return [indent + "———"] }
                let key = item.keyEquivalent.isEmpty ? "" : "  [\(KeyNames.modifierGlyphs(KeyNames.modifiers(from: item.keyEquivalentModifierMask)))\(item.keyEquivalent.uppercased())]"
                let flags = (item.isEnabled ? "" : "  (disabled)") + (item.image != nil ? "  (thumbnail)" : "")
                return [indent + item.title + key + flags] + (item.submenu.map { describe($0, indent: indent + "    ") } ?? [])
            }
        }
        return describe(menu, indent: "").joined(separator: "\n")
    }

    public var debugButton: NSView? { statusItem?.button }

    /// The top-level menu as rows, for the off-screen menu preview.
    var debugMenuRows: [StatusMenuPreview.Row] {
        menuNeedsUpdate(menu)
        return menu.items.map { item in
            if item.isSeparatorItem { return .init(separator: true) }
            var shortcut = ""
            if !item.keyEquivalent.isEmpty {
                let mods = KeyNames.modifierGlyphs(KeyNames.modifiers(from: item.keyEquivalentModifierMask))
                let key = item.keyEquivalent == "," ? "," : KeyNames.table.first { $0.value.menu == item.keyEquivalent }?.value.display ?? item.keyEquivalent.uppercased()
                shortcut = mods + key
            }
            return .init(title: item.title, image: item.image, shortcut: shortcut, enabled: item.isEnabled, hasSubmenu: item.hasSubmenu)
        }
    }

    /// For `--debug-snapshot-ui`: the status menu drawn off screen from its real
    /// items (an approximation of the system menu, which can't be captured
    /// without opening it).
    public func debugMenuSnapshot(appearance: NSAppearance.Name, scale: CGFloat = 2) async -> Data? {
        await StatusMenuPreview.render(rows: debugMenuRows, appearance: appearance, scale: scale)
    }

    /// Replaces the history submenu (last 10, newest first).
    public func updateHistory(_ items: [CaptureResult]) {
        history = Array(items.prefix(Self.historyLimit))
        rebuildHistoryMenu()
        thumbnails.load(history) { [weak self] id in self?.applyThumbnail(id) }
    }

    /// Re-reads shortcut labels (after settings or hotkey changes).
    public func refreshShortcuts() {
        rebuildMenu()
    }

    // MARK: Menu

    public func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        rebuildMenu()
    }

    public func menuWillOpen(_ menu: NSMenu) {
        guard menu === self.menu else { return }
        onMenuWillOpen?()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        menu.addItem(captureItem(.captureArea))
        menu.addItem(captureItem(.captureWindow))
        menu.addItem(captureItem(.captureFullscreen))
        menu.addItem(captureItem(.captureAllInOne))
        menu.addItem(.separator())
        let historyItem = NSMenuItem(title: String(localized: "Capture History"), action: nil, keyEquivalent: "")
        historyItem.submenu = historyMenu
        historyItem.image = ShellIcon.history.nsImage()
        menu.addItem(historyItem)
        let openLast = item(String(localized: "Open Last Capture in Editor"), #selector(openLast), icon: .openInEditor)
        openLast.isEnabled = !history.isEmpty
        menu.addItem(openLast)
        let restore = item(HotkeyAction.restoreLastClosed.title, #selector(restoreLastClosed), icon: .restore)
        applyShortcut(of: .restoreLastClosed, to: restore)
        restore.isEnabled = canRestoreLastClosed()
        menu.addItem(restore)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Settings…"), #selector(openSettings), key: ",", icon: .settings))
        if let updates, updates.isAvailable {
            let title = updates.pendingVersion.map { String(localized: "Update Available (\($0))…") }
                ?? String(localized: "Check for Updates…")
            menu.addItem(item(title, #selector(checkForUpdates), icon: .checkForUpdates))
        }
        menu.addItem(item(String(localized: "Quit \(AppVariant.current.displayName)"), #selector(quit), key: "q", icon: .quit))
    }

    private func rebuildHistoryMenu() {
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
            item.image = thumbnails.image(for: capture.id)
            item.toolTip = "\(Int(capture.pixelSize.width)) × \(Int(capture.pixelSize.height))"
            historyMenu.addItem(item)
        }
        for item in menu.items where item.action == #selector(openLast) {
            item.isEnabled = !history.isEmpty
        }
    }

    private func applyThumbnail(_ id: CaptureResult.ID) {
        guard let index = history.firstIndex(where: { $0.id == id }),
              index < historyMenu.items.count else { return }
        historyMenu.items[index].image = thumbnails.image(for: id)
    }

    private func captureItem(_ action: HotkeyAction) -> NSMenuItem {
        let item = NSMenuItem(title: action.title, action: #selector(capture(_:)), keyEquivalent: "")
        item.target = self
        item.image = Self.icon(for: action).nsImage()
        item.representedObject = action.rawValue
        applyShortcut(of: action, to: item)
        return item
    }

    private func applyShortcut(of action: HotkeyAction, to item: NSMenuItem) {
        guard let combo = hotkeys.binding(for: action) else { return }
        item.keyEquivalent = KeyNames.menuKeyEquivalent(combo)
        item.keyEquivalentModifierMask = KeyNames.menuModifierMask(combo.modifiers)
        if hotkeys.registrationFailures[action] != nil {
            item.toolTip = String(localized: "This shortcut could not be registered. See Settings ▸ Shortcuts.")
        }
    }

    private func item(_ title: String, _ selector: Selector, key: String = "", icon: ShellIcon? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = self
        item.image = icon?.nsImage()
        return item
    }

    static func icon(for action: HotkeyAction) -> ShellIcon {
        switch action {
        case .captureArea: .captureArea
        case .captureWindow: .captureWindow
        case .captureFullscreen: .captureFullscreen
        case .captureAllInOne: .captureAllInOne
        case .restoreLastClosed: .restore
        }
    }

    @objc private func checkForUpdates() { updates?.checkForUpdates() }

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
    @objc private func restoreLastClosed() { onRestoreLastClosed?() }
    @objc private func openSettings() { onOpenSettings?() }
    @objc private func quit() { NSApp.terminate(nil) }
}
