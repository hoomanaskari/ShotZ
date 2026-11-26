import Darwin
import Foundation

/// Advisory cross-process lock around the history index (`flock` on a
/// sibling `history.lock`). The installed app and a build can run at the same
/// time against one folder; every read-modify-write of the index happens
/// while holding this lock, so neither process loses the other's entries.
/// `flock` locks belong to the open file description, so two stores in one
/// process exclude each other too, and the OS drops the lock if a process dies.
struct HistoryIndexLock {
    let url: URL

    /// Runs `body` while holding the lock. If the lock file cannot be opened
    /// (e.g. the folder is read-only) `body` still runs, unlocked: losing the
    /// lock must never lose a capture.
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        let fd = open(url.path(percentEncoded: false), O_CREAT | O_RDWR | O_CLOEXEC, 0o644)
        guard fd >= 0 else { return try body() }
        defer { close(fd) }
        while flock(fd, LOCK_EX) != 0 {
            if errno != EINTR { return try body() }
        }
        defer { flock(fd, LOCK_UN) }
        return try body()
    }
}

/// Identifies one version of the index file. Atomic writes replace the file,
/// so the inode changes on every write by any process.
struct HistoryIndexStamp: Equatable {
    let inode: UInt64
    let size: UInt64
    let modified: Date

    init?(_ url: URL) {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path(percentEncoded: false)) else {
            return nil   // no file yet: nothing to compare
        }
        inode = (attrs[.systemFileNumber] as? NSNumber)?.uint64Value ?? 0
        size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        modified = attrs[.modificationDate] as? Date ?? .distantPast
    }
}
