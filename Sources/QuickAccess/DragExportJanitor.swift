import Foundation
import ShotzCore

/// Cleans the per-drag export folders under `ShotzPaths.dragExports`
/// (each drag writes an export-named copy into its own folder).
enum DragExportJanitor {
    static let maxAge: TimeInterval = 86_400
    /// A cancelled drag's copy is removed after this; a receiver that accepted
    /// a drop may still be reading, so successful drops wait for the launch sweep.
    static let cancelledDelay: Duration = .seconds(180)

    /// Removes entries directly in `root` last modified before `now - maxAge`.
    /// Returns how many were removed.
    @discardableResult
    static func purge(root: URL, olderThan maxAge: TimeInterval = maxAge, now: Date = Date()) -> Int {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else {
            return 0 // nothing there yet
        }
        var removed = 0
        for entry in entries {
            let modified = (try? entry.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            guard now.timeIntervalSince(modified) > maxAge else { continue }
            do {
                try fm.removeItem(at: entry)
                removed += 1
            } catch {
                ShotzLog.logger("QuickAccess").error("Cannot remove drag export \(entry.lastPathComponent, privacy: .private): \(error.localizedDescription, privacy: .private)")
            }
        }
        return removed
    }

    /// The drag's own folder, if `file` lives in one directly under `root`.
    static func dragFolder(of file: URL, root: URL) -> URL? {
        let folder = file.deletingLastPathComponent().standardizedFileURL
        guard folder.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path else { return nil }
        return folder
    }

    /// Removes the folder of a cancelled drag after `delay`.
    static func removeLater(file: URL, root: URL, delay: Duration = cancelledDelay) {
        guard let folder = dragFolder(of: file, root: root) else { return }
        Task.detached(priority: .utility) {
            try? await Task.sleep(for: delay) // only shortens the wait if cancelled
            do {
                try FileManager.default.removeItem(at: folder)
            } catch CocoaError.fileNoSuchFile {
                // already swept
            } catch {
                ShotzLog.logger("QuickAccess").error("Cannot remove cancelled drag folder: \(error.localizedDescription, privacy: .private)")
            }
        }
    }
}
