/// A global shortcut: a virtual key code plus modifier flags.
///
/// `keyCode` is a Carbon/`NSEvent.keyCode` virtual key code (`kVK_*`).
/// `modifiers` uses this type's own stable bit set (not Carbon or AppKit
/// raw values) so stored preferences never depend on framework constants.
public struct KeyCombo: Codable, Sendable, Hashable, CustomStringConvertible {
    public struct Modifiers: OptionSet, Codable, Sendable, Hashable {
        public let rawValue: UInt32
        public init(rawValue: UInt32) { self.rawValue = rawValue }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let shift = Modifiers(rawValue: 1 << 1)
        public static let option = Modifiers(rawValue: 1 << 2)
        public static let control = Modifiers(rawValue: 1 << 3)
    }

    public var keyCode: UInt32
    public var modifiers: Modifiers

    public init(keyCode: UInt32, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    // ANSI virtual key codes (kVK_ANSI_3/4/5).
    public static let keyCode3: UInt32 = 0x14
    public static let keyCode4: UInt32 = 0x15
    public static let keyCode5: UInt32 = 0x17

    public static let defaultFullscreen = KeyCombo(keyCode: keyCode3, modifiers: [.command, .shift])
    public static let defaultArea = KeyCombo(keyCode: keyCode4, modifiers: [.command, .shift])
    public static let defaultAllInOne = KeyCombo(keyCode: keyCode5, modifiers: [.command, .shift])

    public static let devFullscreen = KeyCombo(keyCode: keyCode3, modifiers: [.control, .option, .command])
    public static let devArea = KeyCombo(keyCode: keyCode4, modifiers: [.control, .option, .command])
    public static let devAllInOne = KeyCombo(keyCode: keyCode5, modifiers: [.control, .option, .command])

    /// Display string such as "⌃⌥⌘4".
    public var description: String {
        var s = ""
        if modifiers.contains(.control) { s += "⌃" }
        if modifiers.contains(.option) { s += "⌥" }
        if modifiers.contains(.shift) { s += "⇧" }
        if modifiers.contains(.command) { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    static func keyName(_ code: UInt32) -> String {
        let digits: [UInt32: String] = [
            0x1D: "0", 0x12: "1", 0x13: "2", 0x14: "3", 0x15: "4",
            0x17: "5", 0x16: "6", 0x1A: "7", 0x1C: "8", 0x19: "9",
        ]
        let letters: [UInt32: String] = [
            0x00: "A", 0x0B: "B", 0x08: "C", 0x02: "D", 0x0E: "E", 0x03: "F",
            0x05: "G", 0x04: "H", 0x22: "I", 0x26: "J", 0x28: "K", 0x25: "L",
            0x2E: "M", 0x2D: "N", 0x1F: "O", 0x23: "P", 0x0C: "Q", 0x0F: "R",
            0x01: "S", 0x11: "T", 0x20: "U", 0x09: "V", 0x0D: "W", 0x07: "X",
            0x10: "Y", 0x06: "Z",
        ]
        return digits[code] ?? letters[code] ?? "#\(code)"
    }
}
