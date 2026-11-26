import Foundation

/// Which Shotz this is, decided by the bundle id (SPEC §1, ARCHITECTURE §8).
///
/// - `production`: `ShotZ.app`, `app.shotz.Shotz`, ⌘⇧3/4/5, data in
///   `Application Support/Shotz`. The one the owner installs.
/// - `development`: `ShotZ Dev.app`, `app.shotz.Shotz.dev`, ⌃⌥⌘3/4/5, data in
///   `Application Support/ShotZ Dev`. Built by `scripts/run.sh` for trying
///   changes next to the installed app.
///
/// Each variant has its own bundle id, so its own preferences domain
/// (`UserDefaults.standard`), login item and Screen Recording permission.
///
/// A *test run* (`--no-hotkeys`, any `--debug-*` flag, `-QuickAccessSelfTest`
/// or `SHOTZ_EDITOR_SCRIPT`) is hermetic: its own preferences suite
/// (`<bundle id>.testrun`) and data folder (`<name> Test Runs`), so engineer
/// and test launches never touch the owner's settings or captures.
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

    /// "ShotZ" or "ShotZ Dev": the product name people see.
    public var displayName: String {
        switch self {
        case .production: "ShotZ"
        case .development: "ShotZ Dev"
        }
    }

    /// Folder name under Application Support and the temporary directory.
    /// Production keeps the original "Shotz" folder (existing history).
    public var dataDirectoryName: String {
        switch self {
        case .production: "Shotz"
        case .development: "ShotZ Dev"
        }
    }

    /// Data folder name for hermetic test runs.
    public var testRunDirectoryName: String { "\(displayName) Test Runs" }

    /// Preferences suite for hermetic test runs.
    public var testRunSuiteName: String { bundleIdentifier + ".testrun" }

    // MARK: Test runs

    /// True for engineer/test launches (see the type comment). Decided once.
    public static let isTestRun: Bool = isTestRun(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    public static func isTestRun(arguments: [String], environment: [String: String]) -> Bool {
        let args = arguments.dropFirst()
        return args.contains("--no-hotkeys")
            || args.contains(where: { $0.hasPrefix("--debug-") })
            || args.contains("-QuickAccessSelfTest")
            || environment["SHOTZ_EDITOR_SCRIPT"] != nil
    }

    /// The preferences this process uses: the test-run suite in test runs,
    /// else `.standard` (the variant's own domain). Argument-domain overrides
    /// apply either way (suites include the argument domain).
    /// `nonisolated(unsafe)`: immutable reference to a thread-safe object.
    nonisolated(unsafe) public static let preferences: UserDefaults = preferences(variant: current, testRun: isTestRun)

    public static func preferences(variant: AppVariant, testRun: Bool) -> UserDefaults {
        guard testRun else { return .standard }
        // Only nil for a suite named like the app's own bundle id, which this never is.
        return UserDefaults(suiteName: variant.testRunSuiteName) ?? .standard
    }

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
