import Foundation
import os
import ShotzCore

/// One-time move from the pre-release identity (`app.shotz.Shotz[.dev]`,
/// `Application Support/Shotz` or `ShotZ Dev`) to `com.pixelforty.shotz[.dev]`.
///
/// Runs on launch before anything reads settings or history; never in test runs.
///
/// **Preferences:** every key ShotZ owns (`SettingsKey.isOwned`) is copied from the
/// old domain into the new one, never over a key already set there. The old
/// domain is left untouched. A marker key in the new domain makes this once-only,
/// so restoring defaults later does not bring the old values back.
///
/// **Data:** moved, not copied. The old folder's contents are copied into a
/// staging sibling of the new folder, and absolute paths in `history.json` and
/// `Documents/*.json` are rewritten to the new folder. Then either:
/// - with no new folder yet, the staging folder is renamed into place (atomic,
///   same volume);
/// - with a new folder that already has content, the two are merged: files it
///   lacks are moved in, and history is merged by capture id (the new entry wins).
///
/// Only then is `MIGRATED.txt` written in the old folder and everything else in it
/// removed. An interrupted run leaves either an untouched old folder (the next run
/// discards the stale staging folder and starts again) or a complete new folder
/// (the next run merges again, a no-op by id, then finishes). Never half-moved.
public struct LegacyDataMigration {
    public struct Report: Equatable, Sendable {
        public var copiedKeys: [String] = []
        public var data: DataOutcome = .nothingToMove
    }

    public enum DataOutcome: Equatable, Sendable {
        case nothingToMove
        case alreadyMigrated
        case moved(entries: Int)
        case merged(added: Int)
        case failed(String)
    }

    public static let markerFileName = "MIGRATED.txt"
    /// Set in the new domain once the old domain has been copied.
    public static let defaultsMarkerKey = "migration.legacyDefaultsCopied"

    let oldRoot: URL
    let newRoot: URL
    let oldDomain: () -> [String: Any]?
    let newDefaults: UserDefaults
    let newDomainName: String
    let fileManager = FileManager.default
    private let log = ShotzLog.logger("Migration")

    public init(oldRoot: URL, newRoot: URL, oldDomain: @escaping () -> [String: Any]?,
                newDefaults: UserDefaults, newDomainName: String) {
        self.oldRoot = oldRoot
        self.newRoot = newRoot
        self.oldDomain = oldDomain
        self.newDefaults = newDefaults
        self.newDomainName = newDomainName
    }

    /// The migration for this app's variant, against the real preferences and folders.
    public static func forVariant(_ variant: AppVariant) -> LegacyDataMigration {
        let support = URL.applicationSupportDirectory
        let old = variant.legacyBundleIdentifier
        return LegacyDataMigration(
            oldRoot: support.appending(path: variant.legacyDataDirectoryName, directoryHint: .isDirectory),
            newRoot: ShotzPaths.forVariant(variant).root,
            oldDomain: { UserDefaults.standard.persistentDomain(forName: old) },
            newDefaults: .standard,
            newDomainName: variant.bundleIdentifier
        )
    }

    /// Runs the migration for this process, unless it is a test run.
    @discardableResult
    public static func runAtLaunch(testRun: Bool = AppVariant.isTestRun,
                                   migration: () -> LegacyDataMigration = { forVariant(.current) }) -> Report? {
        guard !testRun else { return nil }
        return migration().run()
    }

    @discardableResult
    public func run() -> Report {
        var report = Report()
        report.copiedKeys = migrateDefaults()
        report.data = migrateData()
        log.notice("Legacy migration: \(report.copiedKeys.count) settings copied; data \(String(describing: report.data), privacy: .public)")
        return report
    }

    // MARK: Preferences

    func migrateDefaults() -> [String] {
        let existing = newDefaults.persistentDomain(forName: newDomainName) ?? [:]
        guard existing[Self.defaultsMarkerKey] == nil else { return [] }
        var copied: [String] = []
        for (key, value) in oldDomain() ?? [:] where SettingsKey.isOwned(key) && existing[key] == nil {
            newDefaults.set(value, forKey: key)
            copied.append(key)
        }
        newDefaults.set(true, forKey: Self.defaultsMarkerKey)
        return copied.sorted()
    }

    // MARK: Data

    /// True once this Mac's data has been moved from the earlier identity (the marker exists):
    /// System Settings may then list two look-alike ShotZ entries for Screen Recording.
    public var hasMigrated: Bool {
        fileManager.fileExists(atPath: oldRoot.appending(path: Self.markerFileName).path(percentEncoded: false))
    }

    var stagingRoot: URL {
        newRoot.deletingLastPathComponent().appending(path: newRoot.lastPathComponent + ".migrating", directoryHint: .isDirectory)
    }

    func migrateData() -> DataOutcome {
        let marker = oldRoot.appending(path: Self.markerFileName)
        guard isDirectory(oldRoot) else { return .nothingToMove }
        if exists(marker) {
            finishOldFolder()   // a previous run may have stopped while clearing it
            return .alreadyMigrated
        }
        guard hasContent(oldRoot) else { return .nothingToMove }
        do {
            // 1. Fresh staging copy (a stale one from an interrupted run is discarded).
            try? fileManager.removeItem(at: stagingRoot)
            try fileManager.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
            for item in try fileManager.contentsOfDirectory(atPath: oldRoot.path(percentEncoded: false))
            where !Self.skipped.contains(item) {
                try fileManager.copyItem(at: oldRoot.appending(path: item), to: stagingRoot.appending(path: item))
            }
            // 2. Absolute paths now point into the new folder.
            try rewritePaths(in: stagingRoot)
            // 3. Into place: rename, or merge into an existing folder.
            let outcome: DataOutcome
            if hasContent(newRoot) {
                outcome = .merged(added: try merge(staging: stagingRoot, into: newRoot))
                try? fileManager.removeItem(at: stagingRoot)
            } else {
                try? fileManager.removeItem(at: newRoot)   // empty or absent
                try fileManager.moveItem(at: stagingRoot, to: newRoot)
                outcome = .moved(entries: Self.historyEntries(at: newRoot).count)
            }
            // 4. Only now mark the old folder as migrated and clear it.
            let note = """
            ShotZ moved this folder's captures, documents and history to
            \(newRoot.path(percentEncoded: false))
            on \(Date().formatted(.iso8601)). This folder is no longer used and can be deleted.
            """
            try Data(note.utf8).write(to: marker, options: .atomic)
            finishOldFolder()
            return outcome
        } catch {
            try? fileManager.removeItem(at: stagingRoot)
            log.error("Legacy data migration failed, old data left in place: \(error.localizedDescription, privacy: .public)")
            return .failed(error.localizedDescription)
        }
    }

    /// Lock and system files that are never carried over.
    static let skipped: Set<String> = ["history.lock", ".DS_Store", markerFileName]

    /// Removes everything in the old folder except the marker.
    private func finishOldFolder() {
        guard let items = try? fileManager.contentsOfDirectory(atPath: oldRoot.path(percentEncoded: false)) else { return }
        for item in items where item != Self.markerFileName {
            try? fileManager.removeItem(at: oldRoot.appending(path: item))
        }
    }

    // MARK: Path rewriting

    /// Rewrites every string in `history.json` and `Documents/*.json` that points into
    /// the old folder (as a file URL or a plain path) to the same place in the new one.
    func rewritePaths(in root: URL) throws {
        var files = [root.appending(path: "history.json")]
        let documents = root.appending(path: "Documents", directoryHint: .isDirectory)
        if let names = try? fileManager.contentsOfDirectory(atPath: documents.path(percentEncoded: false)) {
            files += names.filter { $0.hasSuffix(".json") }.map { documents.appending(path: $0) }
        }
        let replacements = Self.prefixReplacements(from: oldRoot, to: newRoot)
        for file in files where exists(file) {
            let data = try Data(contentsOf: file)
            guard let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) else { continue }
            var changed = false
            let rewritten = Self.rewrite(json, replacements, &changed)
            guard changed else { continue }
            let out = try JSONSerialization.data(withJSONObject: rewritten, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try out.write(to: file, options: .atomic)
        }
    }

    /// (old prefix, new prefix) pairs for file URLs and plain paths, with a trailing slash.
    static func prefixReplacements(from old: URL, to new: URL) -> [(String, String)] {
        func dir(_ s: String) -> String { s.hasSuffix("/") ? s : s + "/" }
        let oldURL = old.standardizedFileURL, newURL = new.standardizedFileURL
        return [
            (dir(oldURL.absoluteString), dir(newURL.absoluteString)),
            (dir(oldURL.path(percentEncoded: false)), dir(newURL.path(percentEncoded: false))),
        ]
    }

    static func rewrite(_ value: Any, _ replacements: [(String, String)], _ changed: inout Bool) -> Any {
        switch value {
        case let string as String:
            for (old, new) in replacements where string.range(of: old, options: [.anchored, .caseInsensitive]) != nil {
                changed = true
                return new + string.dropFirst(old.count)
            }
            return string
        case let array as [Any]:
            return array.map { rewrite($0, replacements, &changed) }
        case let dict as [String: Any]:
            return dict.mapValues { rewrite($0, replacements, &changed) }
        default:
            return value
        }
    }

    // MARK: Merge

    /// Moves files `into` lacks and merges history by id. Returns the number of entries added.
    func merge(staging: URL, into target: URL) throws -> Int {
        for folder in ["Captures", "Documents"] {
            let from = staging.appending(path: folder, directoryHint: .isDirectory)
            let to = target.appending(path: folder, directoryHint: .isDirectory)
            guard let names = try? fileManager.contentsOfDirectory(atPath: from.path(percentEncoded: false)) else { continue }
            try fileManager.createDirectory(at: to, withIntermediateDirectories: true)
            for name in names where !exists(to.appending(path: name)) {
                try fileManager.moveItem(at: from.appending(path: name), to: to.appending(path: name))
            }
        }
        let current = Self.historyEntries(at: target)
        let old = Self.historyEntries(at: staging)
        let known = Set(current.map(\.id))
        let added = old.filter { !known.contains($0.id) }
        guard !added.isEmpty else { return 0 }
        let merged = (current + added).sorted { $0.capture.createdAt > $1.capture.createdAt }
        let data = try HistoryDates.encoder().encode(HistoryIndexFile(entries: merged))
        try data.write(to: target.appending(path: "history.json"), options: .atomic)
        return added.count
    }

    static func historyEntries(at root: URL) -> [HistoryEntry] {
        guard let data = try? Data(contentsOf: root.appending(path: "history.json")),
              let file = try? HistoryDates.decoder().decode(HistoryIndexFile.self, from: data)
        else { return [] }
        return file.entries
    }

    // MARK: Helpers

    private func exists(_ url: URL) -> Bool { fileManager.fileExists(atPath: url.path(percentEncoded: false)) }

    private func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return fileManager.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }

    private func hasContent(_ url: URL) -> Bool {
        guard let items = try? fileManager.contentsOfDirectory(atPath: url.path(percentEncoded: false)) else { return false }
        return items.contains { !Self.skipped.contains($0) }
    }
}
