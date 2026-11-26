import ShotzCore

/// Pure binding logic behind `HotkeyCenter` (unit-tested).
public enum HotkeyBindings {
    /// Effective binding for one action this run. `--dev-hotkeys` forces
    /// ⌃⌥⌘3/4/5 for the three capture actions and leaves the others alone.
    public static func effective(for action: HotkeyAction, stored: KeyCombo?, dev: Bool) -> KeyCombo? {
        guard dev else { return stored }
        switch action {
        case .captureFullscreen: return .devFullscreen
        case .captureArea: return .devArea
        case .captureAllInOne: return .devAllInOne
        case .captureWindow, .restoreLastClosed: return stored
        }
    }

    /// True when `--dev-hotkeys` overrides this action's stored binding.
    public static func isDevOverridden(_ action: HotkeyAction, dev: Bool) -> Bool {
        dev && [.captureFullscreen, .captureArea, .captureAllInOne].contains(action)
    }

    public static func effectiveAll(stored: (HotkeyAction) -> KeyCombo?, dev: Bool) -> [HotkeyAction: KeyCombo] {
        var out: [HotkeyAction: KeyCombo] = [:]
        for action in HotkeyAction.allCases {
            if let combo = effective(for: action, stored: stored(action), dev: dev) { out[action] = combo }
        }
        return out
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
