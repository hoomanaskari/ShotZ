import AppKit
import Combine
import ShotzCore

/// Drives the shortcut recorder: one action records at a time. While
/// recording, global hot keys are suspended so pressing the current combo
/// reaches the recorder instead of starting a capture.
@MainActor final class ShortcutRecorderModel: ObservableObject {
    @Published private(set) var recording: HotkeyAction?
    /// Modifiers currently held while recording, for a live preview.
    @Published private(set) var heldModifiers: KeyCombo.Modifiers = []
    @Published private(set) var problem: (action: HotkeyAction, message: String)?

    private let settings: SettingsStore
    private let hotkeys: HotkeyCenter
    private var monitor: Any?
    private var focusObservers: [NSObjectProtocol] = []

    init(settings: SettingsStore, hotkeys: HotkeyCenter) {
        self.settings = settings
        self.hotkeys = hotkeys
    }

    func toggle(_ action: HotkeyAction) {
        if recording == action { stop() } else { start(action) }
    }

    func start(_ action: HotkeyAction) {
        stop()
        // Key events only reach the local monitor while Shotz is active.
        NSApp.activate()
        recording = action
        problem = nil
        heldModifiers = []
        hotkeys.isSuspended = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            let consumed = MainActor.assumeIsolated { self?.handle(event) ?? false }
            return consumed ? nil : event
        }
        // Losing focus ends recording, so global shortcuts never stay
        // suspended while the user is in another app.
        let center = NotificationCenter.default
        for name in [NSApplication.didResignActiveNotification, NSWindow.didResignKeyNotification] {
            focusObservers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        focusObservers.forEach(NotificationCenter.default.removeObserver)
        focusObservers.removeAll()
        recording = nil
        heldModifiers = []
        hotkeys.isSuspended = false
    }

    func clear(_ action: HotkeyAction) {
        if recording == action { stop() }
        problem = nil
        settings.setHotkey(nil, for: action)
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let action = recording else { return false }
        let mods = KeyNames.modifiers(from: event.modifierFlags.intersection(.deviceIndependentFlagsMask))
        if event.type == .flagsChanged {
            heldModifiers = mods
            return false
        }
        let code = UInt32(event.keyCode)
        if mods.isEmpty, code == KeyNames.escapeKeyCode {
            stop()
            return true
        }
        if mods.isEmpty, code == KeyNames.deleteKeyCode || code == KeyNames.forwardDeleteKeyCode {
            clear(action)
            stop()
            return true
        }
        let combo = KeyCombo(keyCode: code, modifiers: mods)
        let current = HotkeyBindings.storedAll { settings.hotkey(for: $0) }
        if let issue = ShortcutValidation.problem(for: combo, action: action, current: current) {
            problem = (action, issue.message)
            NSSound.beep()
            return true
        }
        problem = nil
        settings.setHotkey(combo, for: action)
        stop()
        return true
    }
}
