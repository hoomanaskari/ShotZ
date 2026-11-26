import AppKit
import ShotzCore

/// Display names and menu key equivalents for virtual key codes (`kVK_*`).
/// Covers every key the shortcut recorder accepts.
public enum KeyNames {
    struct Key {
        let display: String
        let menu: String
    }

    private static func fn(_ code: Int) -> String { String(Character(UnicodeScalar(UInt32(code)) ?? " ")) }

    static let table: [UInt32: Key] = {
        var t: [UInt32: Key] = [:]
        let letters: [(UInt32, String)] = [
            (0x00, "A"), (0x0B, "B"), (0x08, "C"), (0x02, "D"), (0x0E, "E"), (0x03, "F"),
            (0x05, "G"), (0x04, "H"), (0x22, "I"), (0x26, "J"), (0x28, "K"), (0x25, "L"),
            (0x2E, "M"), (0x2D, "N"), (0x1F, "O"), (0x23, "P"), (0x0C, "Q"), (0x0F, "R"),
            (0x01, "S"), (0x11, "T"), (0x20, "U"), (0x09, "V"), (0x0D, "W"), (0x07, "X"),
            (0x10, "Y"), (0x06, "Z"),
            (0x1D, "0"), (0x12, "1"), (0x13, "2"), (0x14, "3"), (0x15, "4"),
            (0x17, "5"), (0x16, "6"), (0x1A, "7"), (0x1C, "8"), (0x19, "9"),
            (0x1B, "-"), (0x18, "="), (0x21, "["), (0x1E, "]"), (0x27, "'"), (0x29, ";"),
            (0x2A, "\\"), (0x2B, ","), (0x2C, "/"), (0x2F, "."), (0x32, "`"),
        ]
        for (code, name) in letters { t[code] = Key(display: name, menu: name.lowercased()) }
        let functionKeys: [(UInt32, Int)] = [
            (0x7A, 1), (0x78, 2), (0x63, 3), (0x76, 4), (0x60, 5), (0x61, 6),
            (0x62, 7), (0x64, 8), (0x65, 9), (0x6D, 10), (0x67, 11), (0x6F, 12),
            (0x69, 13), (0x6B, 14), (0x71, 15), (0x6A, 16), (0x40, 17), (0x4F, 18), (0x50, 19),
        ]
        for (code, n) in functionKeys {
            t[code] = Key(display: "F\(n)", menu: fn(NSF1FunctionKey + n - 1))
        }
        t[0x31] = Key(display: String(localized: "Space"), menu: " ")
        t[0x24] = Key(display: "↩", menu: "\r")
        t[0x30] = Key(display: "⇥", menu: "\t")
        t[0x33] = Key(display: "⌫", menu: fn(NSBackspaceCharacter))
        t[0x75] = Key(display: "⌦", menu: fn(NSDeleteFunctionKey))
        t[0x7B] = Key(display: "←", menu: fn(NSLeftArrowFunctionKey))
        t[0x7C] = Key(display: "→", menu: fn(NSRightArrowFunctionKey))
        t[0x7D] = Key(display: "↓", menu: fn(NSDownArrowFunctionKey))
        t[0x7E] = Key(display: "↑", menu: fn(NSUpArrowFunctionKey))
        t[0x73] = Key(display: "↖", menu: fn(NSHomeFunctionKey))
        t[0x77] = Key(display: "↘", menu: fn(NSEndFunctionKey))
        t[0x74] = Key(display: "⇞", menu: fn(NSPageUpFunctionKey))
        t[0x79] = Key(display: "⇟", menu: fn(NSPageDownFunctionKey))
        return t
    }()

    static let functionKeyCodes: Set<UInt32> = [
        0x7A, 0x78, 0x63, 0x76, 0x60, 0x61, 0x62, 0x64, 0x65, 0x6D, 0x67, 0x6F, 0x69, 0x6B, 0x71, 0x6A, 0x40, 0x4F, 0x50,
    ]

    public static let escapeKeyCode: UInt32 = 0x35
    public static let deleteKeyCode: UInt32 = 0x33
    public static let forwardDeleteKeyCode: UInt32 = 0x75

    public static func isSupported(_ keyCode: UInt32) -> Bool { table[keyCode] != nil }
    public static func isFunctionKey(_ keyCode: UInt32) -> Bool { functionKeyCodes.contains(keyCode) }

    /// "⌃⌥⌘4", "⇧F5", …
    public static func display(_ combo: KeyCombo) -> String {
        modifierGlyphs(combo.modifiers) + (table[combo.keyCode]?.display ?? "Key \(combo.keyCode)")
    }

    public static func modifierGlyphs(_ m: KeyCombo.Modifiers) -> String {
        var s = ""
        if m.contains(.control) { s += "⌃" }
        if m.contains(.option) { s += "⌥" }
        if m.contains(.shift) { s += "⇧" }
        if m.contains(.command) { s += "⌘" }
        return s
    }

    /// Key equivalent string for an `NSMenuItem` (empty when unknown).
    public static func menuKeyEquivalent(_ combo: KeyCombo) -> String {
        table[combo.keyCode]?.menu ?? ""
    }

    public static func menuModifierMask(_ m: KeyCombo.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if m.contains(.command) { flags.insert(.command) }
        if m.contains(.shift) { flags.insert(.shift) }
        if m.contains(.option) { flags.insert(.option) }
        if m.contains(.control) { flags.insert(.control) }
        return flags
    }

    public static func modifiers(from flags: NSEvent.ModifierFlags) -> KeyCombo.Modifiers {
        var m: KeyCombo.Modifiers = []
        if flags.contains(.command) { m.insert(.command) }
        if flags.contains(.shift) { m.insert(.shift) }
        if flags.contains(.option) { m.insert(.option) }
        if flags.contains(.control) { m.insert(.control) }
        return m
    }
}
