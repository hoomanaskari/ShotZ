import ShotzCore

/// Rules for a shortcut typed into the recorder (unit-tested).
public enum ShortcutValidation {
    public enum Problem: Equatable, Sendable {
        /// Needs ⌘, ⌃ or ⌥ (function keys may stand alone).
        case needsModifier
        /// ⌘⇧6 is kept free for the later recording phase (SPEC §2).
        case reserved
        /// Already used by another Shotz action.
        case duplicate(HotkeyAction)
        case unsupportedKey

        public var message: String {
            switch self {
            case .needsModifier: String(localized: "Use at least one of ⌘, ⌃ or ⌥.")
            case .reserved: String(localized: "⌘⇧6 is reserved for screen recording.")
            case .duplicate(let other): String(localized: "Already used for \(other.title).")
            case .unsupportedKey: String(localized: "That key can't be used in a shortcut.")
            }
        }
    }

    public static let reservedCombos: Set<KeyCombo> = [
        KeyCombo(keyCode: 0x16, modifiers: [.command, .shift]),
    ]

    public static func problem(
        for combo: KeyCombo,
        action: HotkeyAction,
        current: [HotkeyAction: KeyCombo]
    ) -> Problem? {
        guard KeyNames.isSupported(combo.keyCode) else { return .unsupportedKey }
        let strong: KeyCombo.Modifiers = [.command, .control, .option]
        if combo.modifiers.intersection(strong).isEmpty, !KeyNames.isFunctionKey(combo.keyCode) {
            return .needsModifier
        }
        if reservedCombos.contains(combo) { return .reserved }
        for other in HotkeyAction.allCases where other != action && current[other] == combo {
            return .duplicate(other)
        }
        return nil
    }
}

extension HotkeyAction {
    /// User-facing name (Settings, menu).
    public var title: String {
        switch self {
        case .captureFullscreen: String(localized: "Capture Fullscreen")
        case .captureArea: String(localized: "Capture Area")
        case .captureAllInOne: String(localized: "All-in-One")
        case .captureWindow: String(localized: "Capture Window")
        case .restoreLastClosed: String(localized: "Restore Last Closed Card")
        }
    }
}
