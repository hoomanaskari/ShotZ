import Darwin
import Foundation

/// Owner-only permissions for ShotZ's own storage: folders 0700, files 0600.
///
/// Covers the data folder (`Application Support/<bundle id>`: Captures, Documents, the history
/// index, `.incoming`) and the folders under the per-user temp dir. Files the user exports to a
/// folder they chose keep normal permissions, and so do the temp files handed to the user by
/// drag-out (a dragged copy keeps its source's mode; their 0700 folders protect them meanwhile).
///
/// An atomic write (or `replaceItemAt`) creates a new file with the default mode, so callers
/// protect the file after writing. Nothing here follows a symbolic link.
public enum PrivateStorage {
    public static let directoryMode: mode_t = 0o700
    public static let fileMode: mode_t = 0o600

    /// Creates `url` (and any missing parents) as 0700; an existing folder is tightened to 0700.
    public static func makeDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: Int(directoryMode)])
        set(directoryMode, on: url, expect: S_IFDIR)
    }

    /// Makes a regular file 0600 (no-op for a symbolic link or anything else).
    public static func protectFile(_ url: URL) {
        set(fileMode, on: url, expect: S_IFREG)
    }

    /// Writes atomically, then makes the new file 0600.
    public static func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        protectFile(url)
    }

    /// The mode bits of `url` (without following a link), for checks and tests.
    public static func mode(of url: URL) -> mode_t? {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
        return info.st_mode & 0o7777
    }

    /// One pass over an existing tree: folders 0700 and (when `files`) regular files 0600.
    /// Never follows or changes a symbolic link, never leaves `root`, and stops after `limit`
    /// entries. Returns how many entries it changed.
    @discardableResult
    public static func repair(root: URL, files: Bool = true, limit: Int = 200_000) -> Int {
        var changed = 0
        guard mode(of: root) != nil, isDirectory(root) else { return 0 }
        if set(directoryMode, on: root, expect: S_IFDIR) { changed += 1 }
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey],
                                                          options: [], errorHandler: { _, _ in true })
        else { return changed }
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        var seen = 0
        for case let url as URL in walker {
            seen += 1
            if seen > limit { break }
            guard url.standardizedFileURL.path(percentEncoded: false).hasPrefix(rootPath) else { walker.skipDescendants(); continue }
            if (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true {
                walker.skipDescendants()   // a link is left alone and never followed
                continue
            }
            if isDirectory(url) {
                if set(directoryMode, on: url, expect: S_IFDIR) { changed += 1 }
            } else if files, set(fileMode, on: url, expect: S_IFREG) {
                changed += 1
            }
        }
        return changed
    }

    private static func isDirectory(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path(percentEncoded: false), &info) == 0 && (info.st_mode & S_IFMT) == S_IFDIR
    }

    /// Sets `mode` when the item is of type `expect` (checked with lstat, so never through a link)
    /// and differs. Returns true when it changed something.
    @discardableResult
    private static func set(_ mode: mode_t, on url: URL, expect: mode_t) -> Bool {
        let path = url.path(percentEncoded: false)
        var info = stat()
        guard lstat(path, &info) == 0, (info.st_mode & S_IFMT) == expect, info.st_mode & 0o7777 != mode else { return false }
        return lchmod(path, mode) == 0
    }
}
