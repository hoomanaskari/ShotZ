import Foundation

/// State of macOS's own screenshot shortcuts, read from
/// `com.apple.symbolichotkeys` (SPEC §2, §8). Read-only: Shotz never writes
/// this domain.
public struct SystemScreenshotShortcuts: Equatable, Sendable {
    public struct Item: Equatable, Sendable, Identifiable {
        public let id: Int
        public let name: String
        public let shortcut: String
        public let enabled: Bool
    }

    public let items: [Item]

    public var anyEnabled: Bool { items.contains(where: \.enabled) }
    public var enabledItems: [Item] { items.filter(\.enabled) }

    /// Symbolic hot key ids for the screenshot shortcuts, with how System
    /// Settings ▸ Keyboard Shortcuts ▸ Screenshots describes them.
    static let known: [(id: Int, name: String, shortcut: String)] = [
        (28, String(localized: "Save picture of screen as a file"), "⇧⌘3"),
        (29, String(localized: "Copy picture of screen to the clipboard"), "⌃⇧⌘3"),
        (30, String(localized: "Save picture of selected area as a file"), "⇧⌘4"),
        (31, String(localized: "Copy picture of selected area to the clipboard"), "⌃⇧⌘4"),
        (184, String(localized: "Screenshot and recording options"), "⇧⌘5"),
    ]

    public static var ids: [Int] { known.map(\.id) }

    /// Reads the current values (fresh from disk).
    public static func read() -> SystemScreenshotShortcuts {
        let domain = "com.apple.symbolichotkeys" as CFString
        CFPreferencesAppSynchronize(domain)
        let value = CFPreferencesCopyAppValue("AppleSymbolicHotKeys" as CFString, domain)
        return parse(value as? [String: Any])
    }

    /// Pure parser over the `AppleSymbolicHotKeys` dictionary. A missing
    /// dictionary or entry means the system default, which is enabled.
    public static func parse(_ hotkeys: [String: Any]?) -> SystemScreenshotShortcuts {
        let items = known.map { k in
            Item(id: k.id, name: k.name, shortcut: k.shortcut, enabled: isEnabled(hotkeys?[String(k.id)]))
        }
        return SystemScreenshotShortcuts(items: items)
    }

    static func isEnabled(_ entry: Any?) -> Bool {
        guard let entry = entry as? [String: Any] else { return true }
        switch entry["enabled"] {
        case let b as Bool: return b
        case let n as NSNumber: return n.intValue != 0
        case let i as Int: return i != 0
        case let s as String: return !(s == "0" || s.lowercased() == "false" || s.lowercased() == "no")
        default: return true
        }
    }
}
