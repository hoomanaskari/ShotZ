import AppKit
import CoreGraphics
import Foundation

/// Permission preflight. Never changes system settings.
public enum Permissions {
    /// Screen Recording granted (no prompt).
    public static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (first time only). Returns current state.
    @discardableResult
    public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    /// Privacy & Security ▸ Screen & System Audio Recording.
    public static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    @MainActor public static func openScreenRecordingSettings() {
        guard let url = screenRecordingSettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    /// macOS's own screenshot symbolic hot key ids (⌘⇧3/4/5 and variants).
    public static let screenshotSymbolicHotKeyIDs = [28, 29, 30, 31, 184]

    /// True if any of the system screenshot shortcuts is enabled; nil when
    /// the preference cannot be read. Reads `com.apple.symbolichotkeys` only.
    public static func systemScreenshotShortcutsEnabled() -> Bool? {
        guard let value = CFPreferencesCopyAppValue(
            "AppleSymbolicHotKeys" as CFString, "com.apple.symbolichotkeys" as CFString
        ) as? [String: Any] else { return nil }
        return screenshotShortcutsEnabled(in: value)
    }

    /// Pure helper over the `AppleSymbolicHotKeys` dictionary (unit-tested).
    /// A missing entry means the system default, which is enabled.
    static func screenshotShortcutsEnabled(in hotkeys: [String: Any]) -> Bool {
        screenshotSymbolicHotKeyIDs.contains { id in
            guard let entry = hotkeys[String(id)] as? [String: Any] else { return true }
            return (entry["enabled"] as? Bool) ?? ((entry["enabled"] as? Int) ?? 1 != 0)
        }
    }
}
