import AppKit
import ShotzCore

/// Maps `KeyCombo` to menu key equivalents for display.
enum KeyEquivalent {
    static func character(for keyCode: UInt32) -> String {
        let name = KeyCombo(keyCode: keyCode, modifiers: []).description
        return name.hasPrefix("#") ? "" : name.lowercased()
    }

    static func flags(for modifiers: KeyCombo.Modifiers) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if modifiers.contains(.command) { flags.insert(.command) }
        if modifiers.contains(.shift) { flags.insert(.shift) }
        if modifiers.contains(.option) { flags.insert(.option) }
        if modifiers.contains(.control) { flags.insert(.control) }
        return flags
    }
}
