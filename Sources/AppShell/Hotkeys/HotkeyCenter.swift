import os
import Carbon.HIToolbox
import Combine
import Foundation
import ShotzCore

/// Global shortcuts via Carbon `RegisterEventHotKey` (no extra permission).
///
/// Bindings come from `SettingsStore` and are re-registered live whenever a
/// setting changes (only the actions whose combo changed are touched).
/// What is registered follows `HotkeyMode` (profile × `--dev-hotkeys`): in the
/// dev profile nothing unless `--dev-hotkeys`, and then only ⌃⌥⇧⌘3/4/5.
/// Session overrides never write preferences. Registration failures are
/// published for the Settings warnings.
///
/// Lifetime: one instance for the whole app run; call `shutdown()` before quit.
@MainActor public final class HotkeyCenter: ObservableObject {
    public var onAction: ((HotkeyAction) -> Void)?
    /// Actions whose shortcut could not be registered, with the Carbon status.
    @Published public private(set) var registrationFailures: [HotkeyAction: OSStatus] = [:]
    public let devHotkeys: Bool
    /// Which shortcuts this run registers (profile × `--dev-hotkeys`).
    public let mode: HotkeyMode

    /// While true nothing is registered (the shortcut recorder is listening,
    /// so the current combo reaches the recorder instead of firing).
    public var isSuspended = false {
        didSet { if isSuspended != oldValue { apply() } }
    }

    private let settings: SettingsStore
    private var registered: [HotkeyAction: (combo: KeyCombo, ref: EventHotKeyRef)] = [:]
    private var handler: EventHandlerRef?
    private var settingsObserver: AnyCancellable?
    private let log = ShotzLog.logger("AppShell")
    /// 'SHTZ'
    static let signature: OSType = 0x5348_545A

    public init(settings: SettingsStore, devHotkeys: Bool, devProfile: Bool = DevProfile.isActive) {
        self.settings = settings
        self.devHotkeys = devHotkeys
        self.mode = HotkeyMode.resolve(devProfile: devProfile, devHotkeys: devHotkeys)
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
        HotkeyBindings.effective(for: action, stored: settings.hotkey(for: action), mode: mode)
    }

    /// True when this session's shortcut differs from the stored one.
    public func isDevOverridden(_ action: HotkeyAction) -> Bool {
        HotkeyBindings.isOverridden(action, mode: mode)
    }

    /// True when this session registers no global shortcut at all.
    public var registersNothing: Bool {
        HotkeyAction.allCases.allSatisfy { binding(for: $0) == nil }
    }

    /// Installs the Carbon handler, registers everything and starts following
    /// settings changes.
    public func start() {
        installHandlerIfNeeded()
        apply()
        guard settingsObserver == nil else { return }
        // objectWillChange fires before the new value is stored; hop to the
        // next main-queue turn so `apply` reads the updated value.
        settingsObserver = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.apply() }
            }
    }

    /// Brings Carbon registrations in line with the current settings.
    public func apply() {
        let desired = isSuspended
            ? [:]
            : HotkeyBindings.effectiveAll(stored: { settings.hotkey(for: $0) }, mode: mode)
        let plan = HotkeyBindings.plan(
            registered: registered.mapValues(\.combo),
            desired: desired,
            failed: Set(registrationFailures.keys)
        )
        // Failures for actions no longer bound are stale.
        var failures = registrationFailures.filter { desired[$0.key] != nil }
        guard !plan.isEmpty || failures.count != registrationFailures.count else { return }

        for action in plan.unregister {
            if let entry = registered.removeValue(forKey: action) { UnregisterEventHotKey(entry.ref) }
        }
        for action in HotkeyAction.allCases where plan.register.contains(action) {
            guard let combo = desired[action] else { continue }
            if let entry = registered.removeValue(forKey: action) { UnregisterEventHotKey(entry.ref) }
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: Self.carbonID(for: action))
            let status = RegisterEventHotKey(
                combo.keyCode, Self.carbonModifiers(combo.modifiers), id, GetApplicationEventTarget(), 0, &ref
            )
            if status == noErr, let ref {
                registered[action] = (combo, ref)
                failures[action] = nil
                log.info("Registered \(action.rawValue, privacy: .public) = \(KeyNames.display(combo), privacy: .public)")
            } else {
                failures[action] = status
                log.error("Could not register \(action.rawValue, privacy: .public) = \(KeyNames.display(combo), privacy: .public) (status \(status))")
            }
        }
        if failures != registrationFailures { registrationFailures = failures }
    }

    /// Actions currently registered with Carbon (tests and diagnostics).
    var registeredActions: Set<HotkeyAction> { Set(registered.keys) }

    public func unregisterAll() {
        for entry in registered.values { UnregisterEventHotKey(entry.ref) }
        registered.removeAll()
    }

    /// Unregisters everything and removes the Carbon handler.
    public func shutdown() {
        settingsObserver = nil
        unregisterAll()
        if let handler {
            RemoveEventHandler(handler)
            self.handler = nil
        }
    }

    // MARK: Carbon plumbing

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // Unretained: the center outlives the handler (removed in `shutdown`).
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
        log.info("Hotkey pressed: \(action.rawValue, privacy: .public)")
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
