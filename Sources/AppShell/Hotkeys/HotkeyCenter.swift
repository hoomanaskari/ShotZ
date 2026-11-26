import os
import Carbon.HIToolbox
import Combine
import Foundation
import ShotzCore

/// Global shortcuts via Carbon `RegisterEventHotKey` (no extra permission).
///
/// Bindings come from `SettingsStore` and are re-registered live whenever a
/// setting changes (only the actions whose combo changed are touched).
/// Runs started with `--no-hotkeys` (implied by debug/self-test/script
/// launches) register nothing. Each app variant has its own stored defaults
/// (Shotz ⌘⇧3/4/5, Shotz Dev ⌃⌥⌘3/4/5).
/// Session overrides never write preferences. Registration failures are
/// published for the Settings warnings.
///
/// Lifetime: one instance for the whole app run; call `shutdown()` before quit.
@MainActor public final class HotkeyCenter: ObservableObject {
    public var onAction: ((HotkeyAction) -> Void)?
    /// Actions whose shortcut could not be registered, with the Carbon status.
    @Published public private(set) var registrationFailures: [HotkeyAction: OSStatus] = [:]
    /// False for runs started with `--no-hotkeys` (engineer worktree runs,
    /// debug/self-test/script runs): nothing is registered.
    public let hotkeysEnabled: Bool

    /// While true nothing is registered (the shortcut recorder is listening,
    /// so the current combo reaches the recorder instead of firing).
    public var isSuspended = false {
        didSet { if isSuspended != oldValue { apply() } }
    }

    private let settings: SettingsStore
    private let registrar: HotkeyRegistrar
    private var registered: [HotkeyAction: KeyCombo] = [:]
    private var hasLoggedOnce = false
    private var handler: EventHandlerRef?
    private var settingsObserver: AnyCancellable?
    private let log = ShotzLog.logger("AppShell")
    /// 'SHTZ'
    static let signature: OSType = 0x5348_545A

    public convenience init(settings: SettingsStore, hotkeysEnabled: Bool) {
        self.init(settings: settings, hotkeysEnabled: hotkeysEnabled, registrar: CarbonHotkeyRegistrar())
    }

    init(settings: SettingsStore, hotkeysEnabled: Bool, registrar: HotkeyRegistrar) {
        self.settings = settings
        self.hotkeysEnabled = hotkeysEnabled
        self.registrar = registrar
    }

    /// True when this run must not register global shortcuts: `--no-hotkeys`,
    /// or any debug, self-test or script launch (they run next to a real
    /// Shotz and must never take its key presses).
    public nonisolated static func hotkeysDisabledRequested(
        arguments: [String] = DebugHooks.arguments,
        environment: [String: String] = DebugHooks.environment
    ) -> Bool {
        AppVariant.isTestRun(arguments: arguments, environment: environment)
    }

    /// The shortcut this run registers for `action` (nil with `--no-hotkeys`).
    public func binding(for action: HotkeyAction) -> KeyCombo? {
        HotkeyBindings.effective(for: action, stored: settings.hotkey(for: action), enabled: hotkeysEnabled)
    }

    /// Warning for the Settings row / onboarding when Carbon refused this
    /// action's shortcut; nil when it registered (or nothing is bound).
    public func registrationWarning(for action: HotkeyAction) -> String? {
        guard let status = registrationFailures[action] else { return nil }
        let combo = binding(for: action).map(KeyNames.display) ?? ""
        let code = String(status)   // plain digits, matching the log (no locale grouping)
        return String(localized: "Couldn't register \(combo) (error \(code)). Another app may be using it.")
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
            : HotkeyBindings.effectiveAll(stored: { settings.hotkey(for: $0) }, enabled: hotkeysEnabled)
        let plan = HotkeyBindings.plan(registered: registered, desired: desired, failed: Set(registrationFailures.keys))
        // Failures for actions no longer bound are stale.
        var failures = registrationFailures.filter { desired[$0.key] != nil }
        let changed = !plan.isEmpty || failures.count != registrationFailures.count
        guard changed || !hasLoggedOnce else { return }

        for action in plan.unregister where registered.removeValue(forKey: action) != nil {
            registrar.unregister(id: Self.carbonID(for: action))
        }
        for action in HotkeyAction.allCases where plan.register.contains(action) {
            guard let combo = desired[action] else { continue }
            registered[action] = nil
            let status = registrar.register(combo, id: Self.carbonID(for: action))
            if status == noErr {
                registered[action] = combo
                failures[action] = nil
            } else {
                failures[action] = status
            }
        }
        if failures != registrationFailures { registrationFailures = failures }
        logState()
    }

    /// One notice line per action (launch and every re-registration), so a
    /// "shortcut does nothing" report can be diagnosed from the log.
    private func logState() {
        hasLoggedOnce = true
        if isSuspended {
            log.notice("Hotkeys suspended while a shortcut is being recorded")
            return
        }
        for action in HotkeyAction.allCases {
            let line = HotkeyBindings.logLine(
                for: action, stored: settings.hotkey(for: action), enabled: hotkeysEnabled,
                failure: registrationFailures[action]
            )
            guard registrar.isSystemRegistrar else {
                // A test's fake registrar: nothing reached the system, so keep it out of the
                // persisted log (where it would read like a real registration).
                log.debug("(fake registrar) \(line, privacy: .public)")
                continue
            }
            if registrationFailures[action] != nil {
                log.error("\(line, privacy: .public)")
            } else {
                log.notice("\(line, privacy: .public)")
            }
        }
    }

    /// Actions currently registered with Carbon (tests and diagnostics).
    var registeredActions: Set<HotkeyAction> { Set(registered.keys) }

    /// Whether the Carbon event handler is installed (tests: never in a test process).
    var hasEventHandler: Bool { handler != nil }

    public func unregisterAll() {
        for action in registered.keys { registrar.unregister(id: Self.carbonID(for: action)) }
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
        // Unit tests and test runs never install a Carbon event handler (nor register shortcuts).
        guard handler == nil, registrar.isSystemRegistrar, !CarbonHotkeyRegistrar.refusesInThisProcess else { return }
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
