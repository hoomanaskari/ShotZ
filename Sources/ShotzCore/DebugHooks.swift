import Foundation

/// The one gate for everything that steers ShotZ from outside the UI: launch arguments
/// (`--debug-*`, `--no-hotkeys`, `-QuickAccess…`), argument-domain preference overrides
/// (`-general.exportFolder …`), `SHOTZ_*` environment variables and debug notifications.
///
/// Only the development app (ShotZ Dev, `com.pixelforty.shotz.dev`) honours them. The
/// production app ignores all of them: it reads launch arguments and environment through
/// this gate (which hands it neither), drops the argument domain from its preferences at
/// launch and logs one public line naming what it ignored. A release build is therefore never
/// steerable by arguments; hermetic checks of release code run as ShotZ Dev built in the
/// release configuration (`scripts/bundle.sh release-check`).
public enum DebugHooks {
    /// Launch arguments, argument-domain keys and environment variables ShotZ knows as hooks.
    public static let argumentHooks = ["--debug-present", "--debug-edit", "--debug-edit-capture", "--debug-capture-id",
                                       "--debug-snapshot-ui", "--no-hotkeys"]
    public static let defaultsHooks = ["QuickAccessSelfTest", "QuickAccessSelfTestCapture", "QuickAccessSelfTestGallery",
                                       "QuickAccessSelfTestKeepRunning", "QuickAccessDebug", "QuickAccessDebugAppearance"]
    public static let environmentHooks = ["SHOTZ_EDITOR_SCRIPT", "SHOTZ_EDITOR_DOCUMENT", "SHOTZ_EDITOR_PERF"]

    /// Whether `variant` honours hooks: the development app only.
    public static func allowed(variant: AppVariant) -> Bool { variant == .development }

    /// Whether this process honours hooks (decided once, by bundle id).
    public static let isAllowed: Bool = allowed(variant: .current)

    /// The launch arguments this process may act on: all of them in ShotZ Dev, only argv[0] otherwise.
    public static let arguments: [String] = arguments(ProcessInfo.processInfo.arguments, allowed: isAllowed)

    /// The environment this process may act on: complete in ShotZ Dev, without the `SHOTZ_*` hooks otherwise.
    public static let environment: [String: String] = environment(ProcessInfo.processInfo.environment, allowed: isAllowed)

    public static func arguments(_ all: [String], allowed: Bool) -> [String] {
        allowed ? all : Array(all.prefix(1))
    }

    public static func environment(_ all: [String: String], allowed: Bool) -> [String: String] {
        allowed ? all : all.filter { !$0.key.hasPrefix("SHOTZ_") }
    }

    /// A debug preference (`-QuickAccessDebug YES` style): only read in ShotZ Dev.
    public static func bool(_ key: String, defaults: UserDefaults = .standard, allowed: Bool = isAllowed) -> Bool {
        allowed && defaults.bool(forKey: key)
    }

    public static func string(_ key: String, defaults: UserDefaults = .standard, allowed: Bool = isAllowed) -> String? {
        allowed ? defaults.string(forKey: key) : nil
    }

    /// The hooks present in a launch that the production app ignores (names only, never values).
    public static func ignoredHooks(arguments: [String], environment: [String: String]) -> [String] {
        let args = arguments.dropFirst()
        var found: [String] = []
        for arg in args where arg.hasPrefix("--") && !found.contains(arg) { found.append(arg) }
        // Argument-domain overrides: "-key value" pairs (ShotZ's settings keys and the debug defaults).
        for arg in args where arg.hasPrefix("-") && !arg.hasPrefix("--") && arg.count > 1 && !found.contains(arg) { found.append(arg) }
        for key in environment.keys.sorted() where key.hasPrefix("SHOTZ_") { found.append(key) }
        return found
    }

    /// Empties the argument domain for the whole process (every UserDefaults instance).
    /// `removeVolatileDomain(forName:)` does not drop it; replacing it with an empty one does.
    public static func clearArgumentDomain() {
        UserDefaults.standard.setVolatileDomain([:], forName: UserDefaults.argumentDomain)
    }

    /// Run first thing at launch. In the production app: drops the argument domain (so no
    /// `-key value` launch argument overrides a preference) and logs, once and publicly, which
    /// hooks were ignored. Does nothing in ShotZ Dev.
    @discardableResult
    public static func applyAtLaunch(allowed: Bool = isAllowed,
                                     arguments: [String] = ProcessInfo.processInfo.arguments,
                                     environment: [String: String] = ProcessInfo.processInfo.environment,
                                     clearArgumentDomain: () -> Void = clearArgumentDomain) -> [String] {
        guard !allowed else { return [] }
        clearArgumentDomain()
        let ignored = ignoredHooks(arguments: arguments, environment: environment)
        if !ignored.isEmpty {
            ShotzLog.logger("App").notice("Debug hooks ignored in the production app: \(ignored.joined(separator: " "), privacy: .public)")
        }
        return ignored
    }
}
