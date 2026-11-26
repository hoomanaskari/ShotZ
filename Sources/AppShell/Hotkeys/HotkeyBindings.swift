import ShotzCore

/// Pure binding logic behind `HotkeyCenter` (unit-tested).
public enum HotkeyBindings {
    /// What this run registers for an action: the stored shortcut, or nothing
    /// when shortcuts are off for the run (`--no-hotkeys`).
    public static func effective(for action: HotkeyAction, stored: KeyCombo?, enabled: Bool) -> KeyCombo? {
        enabled ? stored : nil
    }

    public static func effectiveAll(stored: (HotkeyAction) -> KeyCombo?, enabled: Bool) -> [HotkeyAction: KeyCombo] {
        var out: [HotkeyAction: KeyCombo] = [:]
        for action in HotkeyAction.allCases {
            if let combo = effective(for: action, stored: stored(action), enabled: enabled) { out[action] = combo }
        }
        return out
    }

    /// The stored bindings as typed in Settings.
    public static func storedAll(_ stored: (HotkeyAction) -> KeyCombo?) -> [HotkeyAction: KeyCombo] {
        effectiveAll(stored: stored, enabled: true)
    }

    /// Capture shortcuts to offer when another app holds this variant's
    /// defaults: chosen so they never equal the other variant's defaults.
    public static func alternates(for variant: AppVariant) -> [HotkeyAction: KeyCombo] {
        let mods: KeyCombo.Modifiers = variant == .production ? [.option, .shift, .command] : [.control, .option, .shift, .command]
        return [
            .captureFullscreen: KeyCombo(keyCode: KeyCombo.keyCode3, modifiers: mods),
            .captureArea: KeyCombo(keyCode: KeyCombo.keyCode4, modifiers: mods),
            .captureAllInOne: KeyCombo(keyCode: KeyCombo.keyCode5, modifiers: mods),
        ]
    }

    /// "⌥⇧⌘3, ⌥⇧⌘4 and ⌥⇧⌘5" for the alternates button.
    public static func alternatesTitle(for variant: AppVariant) -> String {
        let a = alternates(for: variant)
        let names = [HotkeyAction.captureFullscreen, .captureArea, .captureAllInOne].compactMap { a[$0].map(KeyNames.display) }
        return String(localized: "Use \(names[0]), \(names[1]) and \(names[2])")
    }

    /// One log line describing an action's state this run.
    public static func logLine(
        for action: HotkeyAction, stored: KeyCombo?, enabled: Bool, failure: Int32?
    ) -> String {
        let name = action.rawValue
        guard let combo = stored else { return "Hotkey \(name): not registered (no stored shortcut)" }
        guard enabled else { return "Hotkey \(name): not registered (--no-hotkeys); stored \(KeyNames.display(combo))" }
        if let failure { return "Hotkey \(name) = \(KeyNames.display(combo)): FAILED (Carbon status \(failure))" }
        return "Hotkey \(name) = \(KeyNames.display(combo)): registered"
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
