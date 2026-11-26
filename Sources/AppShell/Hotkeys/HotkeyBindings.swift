import ShotzCore

/// Pure binding logic behind `HotkeyCenter` (unit-tested).
public enum HotkeyBindings {
    /// ⌃⌥⇧⌘3/4/5: the dev profile's `--dev-hotkeys` set. Distinct from the
    /// owner's ⌘⇧3/4/5 and from the standard profile's ⌃⌥⌘3/4/5, so a dev
    /// instance can never share a combo with the owner's instance.
    public static let devProfileFullscreen = KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: [.control, .option, .shift, .command])
    public static let devProfileArea = KeyCombo(keyCode: KeyCombo.keyCode4, modifiers: [.control, .option, .shift, .command])
    public static let devProfileAllInOne = KeyCombo(keyCode: KeyCombo.keyCode5, modifiers: [.control, .option, .shift, .command])

    /// Effective binding for one action this run (the selection matrix):
    ///
    /// | mode                          | capture 3/4/5      | window, restore |
    /// |-------------------------------|--------------------|-----------------|
    /// | standard                      | stored             | stored          |
    /// | standard + `--dev-hotkeys`    | ⌃⌥⌘3/4/5           | stored          |
    /// | dev profile                   | none               | none            |
    /// | dev profile + `--dev-hotkeys` | ⌃⌥⇧⌘3/4/5          | none            |
    public static func effective(for action: HotkeyAction, stored: KeyCombo?, mode: HotkeyMode) -> KeyCombo? {
        switch mode {
        case .standard:
            return stored
        case .standardDevHotkeys:
            switch action {
            case .captureFullscreen: return .devFullscreen
            case .captureArea: return .devArea
            case .captureAllInOne: return .devAllInOne
            case .captureWindow, .restoreLastClosed: return stored
            }
        case .devProfileOff:
            return nil
        case .devProfileDevHotkeys:
            switch action {
            case .captureFullscreen: return devProfileFullscreen
            case .captureArea: return devProfileArea
            case .captureAllInOne: return devProfileAllInOne
            // Stored bindings could equal the owner's: never register them.
            case .captureWindow, .restoreLastClosed: return nil
            }
        }
    }

    /// True when this session's binding is not simply the stored one.
    public static func isOverridden(_ action: HotkeyAction, mode: HotkeyMode) -> Bool {
        mode != .standard
    }

    public static func effectiveAll(stored: (HotkeyAction) -> KeyCombo?, mode: HotkeyMode) -> [HotkeyAction: KeyCombo] {
        var out: [HotkeyAction: KeyCombo] = [:]
        for action in HotkeyAction.allCases {
            if let combo = effective(for: action, stored: stored(action), mode: mode) { out[action] = combo }
        }
        return out
    }

    /// The stored bindings as typed in Settings (no session override).
    public static func storedAll(_ stored: (HotkeyAction) -> KeyCombo?) -> [HotkeyAction: KeyCombo] {
        effectiveAll(stored: stored, mode: .standard)
    }

    /// What to change to go from the registered set to the desired one.
    /// Everything in `unregister` must be removed before `register` is added,
    /// so two actions can swap shortcuts.
    public struct Plan: Equatable {
        public var unregister: Set<HotkeyAction>
        public var register: Set<HotkeyAction>
        public var isEmpty: Bool { unregister.isEmpty && register.isEmpty }
    }

    /// `failed` actions are retried even when their combo did not change.
    public static func plan(
        registered: [HotkeyAction: KeyCombo],
        desired: [HotkeyAction: KeyCombo],
        failed: Set<HotkeyAction> = []
    ) -> Plan {
        var unregister: Set<HotkeyAction> = []
        var register: Set<HotkeyAction> = []
        for (action, combo) in registered where desired[action] != combo {
            unregister.insert(action)
        }
        for (action, combo) in desired where registered[action] != combo || failed.contains(action) {
            register.insert(action)
        }
        // Retrying a failed action that is still "registered" with the same
        // combo cannot happen (failures are never in `registered`).
        return Plan(unregister: unregister, register: register)
    }

    /// Actions that share a combo with an earlier action (in `allCases` order).
    public static func duplicates(in bindings: [HotkeyAction: KeyCombo]) -> Set<HotkeyAction> {
        var seen: [KeyCombo: HotkeyAction] = [:]
        var dupes: Set<HotkeyAction> = []
        for action in HotkeyAction.allCases {
            guard let combo = bindings[action] else { continue }
            if seen[combo] != nil { dupes.insert(action) } else { seen[combo] = action }
        }
        return dupes
    }
}

/// Which global shortcuts this run registers, from the profile and
/// `--dev-hotkeys` (see `HotkeyBindings.effective`).
public enum HotkeyMode: Equatable, Sendable {
    case standard
    case standardDevHotkeys
    case devProfileOff
    case devProfileDevHotkeys

    public static func resolve(devProfile: Bool, devHotkeys: Bool) -> HotkeyMode {
        switch (devProfile, devHotkeys) {
        case (false, false): .standard
        case (false, true): .standardDevHotkeys
        case (true, false): .devProfileOff
        case (true, true): .devProfileDevHotkeys
        }
    }

    /// For the launch log.
    public var logDescription: String {
        switch self {
        case .standard: "stored shortcuts"
        case .standardDevHotkeys: "--dev-hotkeys: ⌃⌥⌘3/4/5 for captures, stored for the rest"
        case .devProfileOff: "dev profile: no global shortcuts registered"
        case .devProfileDevHotkeys: "dev profile --dev-hotkeys: ⌃⌥⇧⌘3/4/5 for captures only"
        }
    }

    /// Note shown in Settings and onboarding; nil for the standard mode.
    public var sessionNote: String? {
        switch self {
        case .standard:
            nil
        case .standardDevHotkeys:
            String(localized: "Launched with --dev-hotkeys: this session uses ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5 for the capture shortcuts. Changes here are saved and apply on a normal launch.")
        case .devProfileOff:
            String(localized: "Dev profile: no global shortcuts are registered this session, so this copy never competes with your everyday Shotz. Launch with --dev-hotkeys to use ⌃⌥⇧⌘3, ⌃⌥⇧⌘4 and ⌃⌥⇧⌘5. Changes here are saved to the dev profile only.")
        case .devProfileDevHotkeys:
            String(localized: "Dev profile with --dev-hotkeys: this session uses ⌃⌥⇧⌘3, ⌃⌥⇧⌘4 and ⌃⌥⇧⌘5 for the capture shortcuts; Capture Window and Restore have none. Changes here are saved to the dev profile only.")
        }
    }
}
