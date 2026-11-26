import Foundation

/// Separates engineer/test runs from the owner's real Shotz.
///
/// The dev profile is active when launched with `--dev-profile`,
/// `SHOTZ_DEV_PROFILE=1`, any `--debug-*` argument, `SHOTZ_EDITOR_SCRIPT`, or
/// `-QuickAccessSelfTest`. It then uses its own preferences
/// (`UserDefaults` suite `app.shotz.Shotz.dev`) and its own data folder
/// (`~/Library/Application Support/Shotz-Dev`, temp `…/Shotz-Dev`), so a
/// test run never changes the owner's settings, history or captures.
/// The bundle id stays `app.shotz.Shotz` (the Screen Recording grant is tied
/// to it). Argument-domain overrides (`-quickAccess.side right`) still apply:
/// suite defaults include the argument domain.
public enum DevProfile {
    public static let suiteName = "app.shotz.Shotz.dev"
    public static let directoryName = "Shotz-Dev"
    public static let standardDirectoryName = "Shotz"

    /// Pure detection over launch arguments and environment (unit-tested).
    public static func isRequested(arguments: [String], environment: [String: String]) -> Bool {
        let args = arguments.dropFirst()
        if args.contains("--dev-profile") || args.contains(where: { $0.hasPrefix("--debug-") }) { return true }
        if args.contains("-QuickAccessSelfTest") { return true }
        if environment["SHOTZ_DEV_PROFILE"] == "1" { return true }
        if environment["SHOTZ_EDITOR_SCRIPT"] != nil { return true }
        return false
    }

    /// Decided once per process.
    public static let isActive: Bool = isRequested(
        arguments: ProcessInfo.processInfo.arguments,
        environment: ProcessInfo.processInfo.environment
    )

    /// The preferences every module must use instead of `UserDefaults.standard`.
    /// `nonisolated(unsafe)`: immutable reference, and `UserDefaults` is
    /// documented as thread-safe (it is just not marked `Sendable`).
    nonisolated(unsafe) public static let defaults: UserDefaults = makeDefaults(active: isActive)

    public static func makeDefaults(active: Bool) -> UserDefaults {
        guard active else { return .standard }
        // A suite name only fails when it equals the app's own bundle id,
        // which this one never does.
        return UserDefaults(suiteName: suiteName) ?? .standard
    }

    /// Short name for logs: "dev" or "standard".
    public static var name: String { isActive ? "dev" : "standard" }
}
