import Foundation
import Testing
@testable import AppShell
import ShotzCore

/// The one-time move from app.shotz.Shotz to com.pixelforty.shotz, against temporary
/// folders and preference suites (never the real ones).
struct LegacyDataMigrationTests {
    let base: URL
    let oldRoot: URL
    let newRoot: URL
    let oldSuite = "ShotzLegacyOld-\(UUID().uuidString)"
    let newSuite = "ShotzLegacyNew-\(UUID().uuidString)"

    init() {
        base = FileManager.default.temporaryDirectory.appending(path: "ShotzMigration-\(UUID().uuidString)", directoryHint: .isDirectory)
        oldRoot = base.appending(path: "Shotz", directoryHint: .isDirectory)
        newRoot = base.appending(path: "com.pixelforty.shotz", directoryHint: .isDirectory)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
        UserDefaults().removePersistentDomain(forName: oldSuite)
        UserDefaults().removePersistentDomain(forName: newSuite)
    }

    var oldDefaults: UserDefaults { UserDefaults(suiteName: oldSuite)! }
    var newDefaults: UserDefaults { UserDefaults(suiteName: newSuite)! }

    func migration() -> LegacyDataMigration {
        let suite = oldSuite
        return LegacyDataMigration(oldRoot: oldRoot, newRoot: newRoot,
                                   oldDomain: { UserDefaults().persistentDomain(forName: suite) },
                                   newDefaults: newDefaults, newDomainName: newSuite)
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }
    func contents(_ url: URL) -> [String] { ((try? FileManager.default.contentsOfDirectory(atPath: url.path(percentEncoded: false))) ?? []).sorted() }

    /// A capture in `root`: PNG, history entry, document JSON (absolute base image URL) and rendered PNG.
    @discardableResult
    func seed(_ root: URL, ids: [UUID], exportURL: URL? = nil) throws -> [HistoryEntry] {
        let paths = ShotzPaths(root: root)
        try paths.createDirectories()
        var entries: [HistoryEntry] = []
        for (i, id) in ids.enumerated() {
            let png = paths.captures.appending(path: "\(id.uuidString).png")
            try FakeCaptureEngine.writePNG(width: 4, height: 3, to: png)
            let capture = CaptureResult(id: id, fileURL: png, displayName: "c\(i)", kind: .area,
                                        pixelSize: CGSize(width: 4, height: 3), scale: 1, displayID: 1,
                                        createdAt: Date(timeIntervalSince1970: 1_000_000 + Double(i)))
            entries.append(HistoryEntry(capture: capture, exportURL: exportURL))
            struct Doc: Encodable { let version = 3; let baseImageURL: URL; let objects: [String] = [] }
            try JSONEncoder().encode(Doc(baseImageURL: png)).write(to: paths.documents.appending(path: "\(id.uuidString).json"))
            try FakeCaptureEngine.writePNG(width: 4, height: 3, to: paths.documents.appending(path: "\(id.uuidString).png"))
        }
        let index = HistoryIndexFile(entries: entries.sorted { $0.capture.createdAt > $1.capture.createdAt })
        try HistoryDates.encoder().encode(index).write(to: paths.historyIndex)
        try Data().write(to: root.appending(path: "history.lock"))
        return entries
    }

    func documentBaseURL(_ root: URL, _ id: UUID) throws -> String {
        let data = try Data(contentsOf: root.appending(path: "Documents/\(id.uuidString).json"))
        let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        return try #require(json["baseImageURL"] as? String)
    }

    func newPrefix() -> String { newRoot.standardizedFileURL.path(percentEncoded: false) }

    // MARK: Cases

    @Test func freshInstallDoesNothingButMarkTheDefaults() {
        defer { cleanup() }
        let report = migration().run()
        #expect(report.copiedKeys.isEmpty)
        #expect(report.data == .nothingToMove)
        #expect(!exists(newRoot))
        #expect(newDefaults.bool(forKey: LegacyDataMigration.defaultsMarkerKey))
    }

    @MainActor @Test func oldOnlyMovesDataRewritesPathsAndCopiesOwnedSettings() async throws {
        defer { cleanup() }
        let ids = [UUID(), UUID()]
        let export = URL(filePath: "/Users/someone/Desktop/ShotZ export.png")
        try seed(oldRoot, ids: ids, exportURL: export)
        let combo = KeyCombo(keyCode: KeyCombo.keyCode4, modifiers: [.command, .option])
        oldDefaults.set("Shot %Y-%m-%d", forKey: SettingsKey.fileNamePattern)
        oldDefaults.set(try JSONEncoder().encode(combo), forKey: SettingsKey.hotkey(.captureArea))
        oldDefaults.set(true, forKey: SettingsKey.hasCompletedOnboarding)
        oldDefaults.set("{{0, 0}, {600, 400}}", forKey: "NSWindow Frame ShotzSettings")   // AppKit's, not ours

        let report = migration().run()

        #expect(report.data == .moved(entries: 2))
        #expect(report.copiedKeys == [SettingsKey.hasCompletedOnboarding, SettingsKey.fileNamePattern, SettingsKey.hotkey(.captureArea)].sorted())
        // Settings: pattern and shortcut preserved, AppKit's key left behind, old domain untouched.
        let settings = SettingsStore(defaults: newDefaults, variant: .production)
        #expect(settings.fileNamePattern == "Shot %Y-%m-%d")
        #expect(settings.hotkey(for: .captureArea) == combo)
        #expect(newDefaults.object(forKey: "NSWindow Frame ShotzSettings") == nil)
        #expect(oldDefaults.string(forKey: SettingsKey.fileNamePattern) == "Shot %Y-%m-%d")
        // Data: everything moved, paths rewritten, export URL outside the folder unchanged.
        let entries = LegacyDataMigration.historyEntries(at: newRoot)
        #expect(Set(entries.map(\.id)) == Set(ids))
        for entry in entries {
            #expect(entry.capture.fileURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(newPrefix()))
            #expect(exists(entry.capture.fileURL))
            #expect(entry.exportURL == export)
        }
        for id in ids {
            let base = try documentBaseURL(newRoot, id)
            #expect(base.hasPrefix(newRoot.standardizedFileURL.absoluteString), "\(base)")
            #expect(exists(newRoot.appending(path: "Documents/\(id.uuidString).png")))
        }
        #expect(!exists(newRoot.appending(path: "history.lock")))   // lock files are never carried over
        // The rewritten index still loads through the real store.
        let store = FileHistoryStore(paths: ShotzPaths(root: newRoot))
        #expect(Set(await store.recent(limit: 100).map(\.id)) == Set(ids))
        // Old folder: only the note remains; no staging folder left behind.
        #expect(contents(oldRoot) == [LegacyDataMigration.markerFileName])
        #expect(!exists(migration().stagingRoot))
    }

    @Test func secondRunIsANoOp() throws {
        defer { cleanup() }
        try seed(oldRoot, ids: [UUID()])
        oldDefaults.set("A %Y", forKey: SettingsKey.fileNamePattern)
        migration().run()
        let index = try Data(contentsOf: newRoot.appending(path: "history.json"))
        // Restoring defaults later must not bring the old value back.
        newDefaults.removeObject(forKey: SettingsKey.fileNamePattern)

        let again = migration().run()
        #expect(again.copiedKeys.isEmpty)
        #expect(again.data == .alreadyMigrated)
        #expect(try Data(contentsOf: newRoot.appending(path: "history.json")) == index)
        #expect(newDefaults.string(forKey: SettingsKey.fileNamePattern) == nil)
    }

    @Test func bothPresentMergeByIDWithoutLosingEntriesOrNewerSettings() throws {
        defer { cleanup() }
        let shared = UUID(), oldOnly = UUID(), newOnly = UUID()
        try seed(oldRoot, ids: [shared, oldOnly])
        try seed(newRoot, ids: [shared, newOnly])
        oldDefaults.set("Old %Y", forKey: SettingsKey.fileNamePattern)
        oldDefaults.set(false, forKey: SettingsKey.playSounds)
        newDefaults.set("New %Y", forKey: SettingsKey.fileNamePattern)

        let report = migration().run()

        #expect(report.data == .merged(added: 1))
        #expect(report.copiedKeys == [SettingsKey.playSounds])
        #expect(newDefaults.string(forKey: SettingsKey.fileNamePattern) == "New %Y")
        let entries = LegacyDataMigration.historyEntries(at: newRoot)
        #expect(Set(entries.map(\.id)) == [shared, oldOnly, newOnly])
        #expect(entries.count == 3)
        #expect(entries.map(\.capture.createdAt) == entries.map(\.capture.createdAt).sorted(by: >))
        let moved = try #require(entries.first { $0.id == oldOnly })
        #expect(moved.capture.fileURL.standardizedFileURL.path(percentEncoded: false).hasPrefix(newPrefix()))
        #expect(exists(moved.capture.fileURL))
        #expect(try documentBaseURL(newRoot, oldOnly).hasPrefix(newRoot.standardizedFileURL.absoluteString))
        #expect(contents(oldRoot) == [LegacyDataMigration.markerFileName])
    }

    @Test func interruptedWhileStagingRestartsCleanly() throws {
        defer { cleanup() }
        let ids = [UUID(), UUID()]
        try seed(oldRoot, ids: ids)
        // A crash while copying left a partial staging folder; the old data is intact.
        let staging = migration().stagingRoot
        try FileManager.default.createDirectory(at: staging.appending(path: "Captures"), withIntermediateDirectories: true)
        try Data("partial".utf8).write(to: staging.appending(path: "Captures/junk.png"))

        let report = migration().run()

        #expect(report.data == .moved(entries: 2))
        #expect(!exists(staging))
        #expect(!exists(newRoot.appending(path: "Captures/junk.png")))
        #expect(Set(LegacyDataMigration.historyEntries(at: newRoot).map(\.id)) == Set(ids))
    }

    @Test func interruptedAfterTheRenameFinishesWithoutDuplicates() throws {
        defer { cleanup() }
        let ids = [UUID(), UUID()]
        try seed(oldRoot, ids: ids)
        // Simulate: the first run renamed staging into place, then stopped before the marker.
        try FileManager.default.copyItem(at: oldRoot, to: base.appending(path: "backup"))
        migration().run()
        try FileManager.default.removeItem(at: oldRoot)
        try FileManager.default.moveItem(at: base.appending(path: "backup"), to: oldRoot)

        let report = migration().run()

        #expect(report.data == .merged(added: 0))
        #expect(LegacyDataMigration.historyEntries(at: newRoot).count == 2)
        #expect(contents(oldRoot) == [LegacyDataMigration.markerFileName])
    }

    @Test func interruptedWhileClearingTheOldFolderFinishesTheJob() throws {
        defer { cleanup() }
        try seed(oldRoot, ids: [UUID()])
        migration().run()
        // Leftovers next to the marker, as if the clean-up stopped half way.
        try FileManager.default.createDirectory(at: oldRoot.appending(path: "Captures"), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: oldRoot.appending(path: "Captures/left.png"))

        #expect(migration().run().data == .alreadyMigrated)
        #expect(contents(oldRoot) == [LegacyDataMigration.markerFileName])
        #expect(LegacyDataMigration.historyEntries(at: newRoot).count == 1)
    }

    @Test func pathRewritingMatchesOnlyTheOldFolder() {
        let old = URL(filePath: "/Users/u/Library/Application Support/Shotz", directoryHint: .isDirectory)
        let new = URL(filePath: "/Users/u/Library/Application Support/com.pixelforty.shotz", directoryHint: .isDirectory)
        let pairs = LegacyDataMigration.prefixReplacements(from: old, to: new)
        var changed = false
        let input: [String: Any] = [
            "a": "file:///Users/u/Library/Application%20Support/Shotz/Captures/x.png",
            "b": "/Users/u/Library/Application Support/Shotz/Documents/y.json",
            "c": "/Users/u/Library/Application Support/Shotz Dev/z.png",   // a different folder
            "d": ["file:///Users/u/Desktop/e.png", 3],
        ]
        let out = LegacyDataMigration.rewrite(input, pairs, &changed) as? [String: Any]
        #expect(changed)
        #expect(out?["a"] as? String == "file:///Users/u/Library/Application%20Support/com.pixelforty.shotz/Captures/x.png")
        #expect(out?["b"] as? String == "/Users/u/Library/Application Support/com.pixelforty.shotz/Documents/y.json")
        #expect(out?["c"] as? String == "/Users/u/Library/Application Support/Shotz Dev/z.png")
        #expect((out?["d"] as? [Any])?.first as? String == "file:///Users/u/Desktop/e.png")
    }

    @Test func testRunsNeverMigrate() throws {
        defer { cleanup() }
        try seed(oldRoot, ids: [UUID()])
        oldDefaults.set("A %Y", forKey: SettingsKey.fileNamePattern)
        var built = false
        #expect(LegacyDataMigration.runAtLaunch(testRun: true, migration: { built = true; return migration() }) == nil)
        #expect(!built)
        #expect(!exists(newRoot))
        #expect(contents(oldRoot).contains("history.json"))
        #expect(newDefaults.object(forKey: LegacyDataMigration.defaultsMarkerKey) == nil)
        #expect(LegacyDataMigration.runAtLaunch(testRun: false, migration: migration)?.data == .moved(entries: 1))
    }

    @Test func realLocationsFollowTheVariant() {
        let dev = LegacyDataMigration.forVariant(.development), prod = LegacyDataMigration.forVariant(.production)
        #expect(dev.newRoot.lastPathComponent == "com.pixelforty.shotz.dev")
        #expect(dev.oldRoot.lastPathComponent == "ShotZ Dev")
        #expect(prod.newRoot.lastPathComponent == "com.pixelforty.shotz")
        #expect(prod.oldRoot.lastPathComponent == "Shotz")
        #expect(prod.stagingRoot.lastPathComponent == "com.pixelforty.shotz.migrating")
        #expect(prod.stagingRoot.deletingLastPathComponent() == prod.newRoot.deletingLastPathComponent())
    }
}
