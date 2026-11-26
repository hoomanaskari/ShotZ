import os

/// `os.Logger` factory: subsystem `app.shotz.Shotz`, category = module.
public enum ShotzLog {
    public static let subsystem = "app.shotz.Shotz"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}
