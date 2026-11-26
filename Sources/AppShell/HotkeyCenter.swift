import os
import Carbon.HIToolbox
import Foundation
import ShotzCore

/// Global shortcuts via Carbon `RegisterEventHotKey` (no extra permission).
/// Bindings come from `SettingsStore`; dev mode forces ⌃⌥⌘3/4/5 for the
/// three capture actions for this run only, never writing preferences.
@MainActor public final class HotkeyCenter {
    public var onAction: ((HotkeyAction) -> Void)?
    /// Actions whose shortcut could not be registered (for Settings warnings).
    public private(set) var registrationFailures: Set<HotkeyAction> = []
    public let devHotkeys: Bool

    private let settings: SettingsStore
    private var refs: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?
    private let log = ShotzLog.logger("AppShell")
    /// 'SHTZ'
    private static let signature: OSType = 0x5348_545A

    public init(settings: SettingsStore, devHotkeys: Bool) {
        self.settings = settings
        self.devHotkeys = devHotkeys
    }

    /// True when launched with `--dev-hotkeys` or `SHOTZ_DEV_HOTKEYS=1`.
    public nonisolated static func devHotkeysRequested(
        arguments: [String] = ProcessInfo.processInfo.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        arguments.contains("--dev-hotkeys") || environment["SHOTZ_DEV_HOTKEYS"] == "1"
    }

    /// Effective binding for this run.
    public func binding(for action: HotkeyAction) -> KeyCombo? {
        Self.effectiveBinding(for: action, stored: settings.hotkey(for: action), dev: devHotkeys)
    }

    nonisolated static func effectiveBinding(for action: HotkeyAction, stored: KeyCombo?, dev: Bool) -> KeyCombo? {
        guard dev else { return stored }
        switch action {
        case .captureFullscreen: return .devFullscreen
        case .captureArea: return .devArea
        case .captureAllInOne: return .devAllInOne
        case .captureWindow, .restoreLastClosed: return stored
        }
    }

    /// (Re-)registers every bound action.
    public func registerAll() {
        unregisterAll()
        installHandlerIfNeeded()
        registrationFailures = []
        for action in HotkeyAction.allCases {
            guard let combo = binding(for: action) else { continue }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: Self.carbonID(for: action))
            let status = RegisterEventHotKey(
                combo.keyCode, Self.carbonModifiers(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                refs[action] = ref
                log.info("Registered \(action.rawValue, privacy: .public) = \(combo.description, privacy: .public)")
            } else {
                registrationFailures.insert(action)
                log.error("Could not register \(action.rawValue, privacy: .public) = \(combo.description, privacy: .public) (status \(status))")
            }
        }
    }

    public func unregisterAll() {
        for ref in refs.values { UnregisterEventHotKey(ref) }
        refs.removeAll()
    }

    // MARK: Carbon plumbing

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let context = Unmanaged.passUnretained(self).toOpaque()
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            guard err == noErr, hotKeyID.signature == HotkeyCenter.signature else { return OSStatus(eventNotHandledErr) }
            let id = hotKeyID.id
            // Carbon delivers application-target hot key events on the main thread.
            MainActor.assumeIsolated {
                let center = Unmanaged<HotkeyCenter>.fromOpaque(context).takeUnretainedValue()
                center.fire(carbonID: id)
            }
            return noErr
        }, 1, &spec, context, &handler)
        if status != noErr { log.error("InstallEventHandler failed: \(status)") }
    }

    private func fire(carbonID: UInt32) {
        guard let action = HotkeyAction.allCases.first(where: { Self.carbonID(for: $0) == carbonID }) else { return }
        log.info("Hotkey \(action.rawValue, privacy: .public)")
        onAction?(action)
    }

    nonisolated static func carbonID(for action: HotkeyAction) -> UInt32 {
        UInt32((HotkeyAction.allCases.firstIndex(of: action) ?? 0) + 1)
    }

    nonisolated static func carbonModifiers(_ m: KeyCombo.Modifiers) -> UInt32 {
        var flags: UInt32 = 0
        if m.contains(.command) { flags |= UInt32(cmdKey) }
        if m.contains(.shift) { flags |= UInt32(shiftKey) }
        if m.contains(.option) { flags |= UInt32(optionKey) }
        if m.contains(.control) { flags |= UInt32(controlKey) }
        return flags
    }
}
