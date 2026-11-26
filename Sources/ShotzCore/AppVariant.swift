import Foundation

/// Which Shotz this is, decided by the bundle id (SPEC §1, ARCHITECTURE §8).
///
/// - `production`: `Shotz.app`, `app.shotz.Shotz`, ⌘⇧3/4/5, data in
///   `Application Support/Shotz`. The one the owner installs.
/// - `development`: `Shotz Dev.app`, `app.shotz.Shotz.dev`, ⌃⌥⌘3/4/5, data in
///   `Application Support/Shotz Dev`. Built by `scripts/run.sh` for trying
///   changes next to the installed app.
///
/// Each variant has its own bundle id, so its own preferences domain
/// (`UserDefaults.standard`), login item and Screen Recording permission.
public enum AppVariant: String, Sendable, CaseIterable {
    case production
    case development

    public static let productionBundleID = "app.shotz.Shotz"
    public static let developmentBundleID = "app.shotz.Shotz.dev"

    /// This process's variant. Anything that is not the dev bundle id
    /// (including unit tests) is production.
    public static let current: AppVariant = from(bundleIdentifier: Bundle.main.bundleIdentifier)

    public static func from(bundleIdentifier: String?) -> AppVariant {
        bundleIdentifier == developmentBundleID ? .development : .production
    }

    public var bundleIdentifier: String {
        switch self {
        case .production: Self.productionBundleID
        case .development: Self.developmentBundleID
        }
    }

    /// "Shotz" or "Shotz Dev": app name in windows, menus and Finder.
    public var displayName: String {
        switch self {
        case .production: "Shotz"
        case .development: "Shotz Dev"
        }
    }

    /// Folder name under Application Support and the temporary directory.
    public var dataDirectoryName: String { displayName }

    /// Default capture shortcuts differ so both apps can run side by side.
    public func defaultHotkey(for action: HotkeyAction) -> KeyCombo? {
        switch (self, action) {
        case (.production, .captureFullscreen): .defaultFullscreen
        case (.production, .captureArea): .defaultArea
        case (.production, .captureAllInOne): .defaultAllInOne
        case (.development, .captureFullscreen): .devFullscreen
        case (.development, .captureArea): .devArea
        case (.development, .captureAllInOne): .devAllInOne
        case (_, .captureWindow), (_, .restoreLastClosed): nil
        }
    }

    /// Launch at login defaults on for the installed app only.
    public var launchAtLoginDefault: Bool { self == .production }
}
