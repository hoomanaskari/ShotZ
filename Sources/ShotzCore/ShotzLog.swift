import os

/// `os.Logger` factory: subsystem `com.pixelforty.shotz` (the production bundle id), category = module.
public enum ShotzLog {
    public static let subsystem = AppVariant.productionBundleID

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
