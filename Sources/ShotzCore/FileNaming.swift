import Foundation

/// File-name pattern formatting and collision-safe naming.
///
/// Patterns support a small strftime subset: `%Y %y %m %d %H %M %S %%`.
/// Unknown sequences are kept literally.
public enum FileNaming {
    public static let defaultPattern = "Shotz %Y-%m-%d at %H.%M.%S"

    /// Formats `pattern` for `date` in `calendar`'s time zone and strips
    /// characters that are not allowed in file names (`/`, `:`).
    public static func format(
        _ pattern: String,
        date: Date,
        calendar: Calendar = .current
    ) -> String {
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        var out = ""
        var iterator = pattern.makeIterator()
        while let ch = iterator.next() {
            guard ch == "%" else { out.append(ch); continue }
            guard let spec = iterator.next() else { out.append("%"); break }
            switch spec {
            case "Y": out += String(format: "%04d", c.year ?? 0)
            case "y": out += two((c.year ?? 0) % 100)
            case "m": out += two(c.month)
            case "d": out += two(c.day)
            case "H": out += two(c.hour)
            case "M": out += two(c.minute)
            case "S": out += two(c.second)
            case "%": out += "%"
            default: out += "%\(spec)"
            }
        }
        return sanitize(out)
    }

    /// Replaces path separators and colons; trims whitespace; never empty.
    public static func sanitize(_ name: String) -> String {
        let cleaned = name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: ".")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Shotz" : cleaned
    }

    /// The candidate name for attempt `n` (1 = base name, 2 = "base 2", …).
    public static func candidate(base: String, ext: String, attempt n: Int) -> String {
        let stem = n <= 1 ? base : "\(base) \(n)"
        return ext.isEmpty ? stem : "\(stem).\(ext)"
    }

    /// First URL in `directory` named `base[ n].ext` for which `exists` is false.
    public static func uniqueURL(
        in directory: URL,
        base: String,
        ext: String,
        exists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
    ) -> URL {
        let base = sanitize(base)
        var n = 1
        while true {
            let url = directory.appending(path: candidate(base: base, ext: ext, attempt: n), directoryHint: .notDirectory)
            if !exists(url) { return url }
            n += 1
        }
    }
}
