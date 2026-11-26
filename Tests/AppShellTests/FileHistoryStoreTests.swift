import Foundation
import Testing
@testable import AppShell
import ShotzCore

struct FileHistoryStoreTests {
    let paths: ShotzPaths

    init() {
        paths = ShotzPaths(root: FileManager.default.temporaryDirectory
            .appending(path: "ShotzHistory-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    func capture(age: TimeInterval = 0, name: String = UUID().uuidString) throws -> CaptureResult {
        try paths.createDirectories()
        let url = paths.captures.appending(path: "\(name).png")
        try FakeCaptureEngine.writePNG(width: 4, height: 3, to: url)
        return CaptureResult(fileURL: url, displayName: name, kind: .area, pixelSize: CGSize(width: 4, height: 3),
                             scale: 1, displayID: 1, createdAt: Date().addingTimeInterval(-age))
    }

    func exists(_ url: URL) -> Bool { FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) }

    func cleanup() { try? FileManager.default.removeItem(at: paths.root) }

    @Test func addRecentPersistRemove() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture(age: 10), b = try capture()
        await store.add(a)
        await store.add(b)
        #expect(await store.recent(limit: 10).map(\.id) == [b.id, a.id])
        #expect(await store.recent(limit: 1).map(\.id) == [b.id])
        #expect(await store.recent(limit: 0).isEmpty)

        let reloaded = FileHistoryStore(paths: paths)
        let back = await reloaded.recent(limit: 10)
        #expect(back.map(\.id) == [b.id, a.id])
        #expect(back.map(\.fileURL) == [b.fileURL, a.fileURL])
        #expect(abs(back[0].createdAt.timeIntervalSince(b.createdAt)) < 0.001)

        await reloaded.remove(id: b.id, deleteFile: true)
        #expect(await reloaded.recent(limit: 10).map(\.id) == [a.id])
        #expect(!exists(b.fileURL))
        await reloaded.remove(id: a.id, deleteFile: false)
        #expect(exists(a.fileURL))
        #expect(await reloaded.count == 0)
        // Removing an unknown id is a no-op.
        await reloaded.remove(id: UUID(), deleteFile: true)
    }

    @Test func addingTheSameCaptureTwiceKeepsOneEntryAndExport() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture()
        await store.add(a)
        let export = URL(filePath: "/tmp/exported.png")
        await store.markExported(id: a.id, url: export)
        await store.add(a)
        #expect(await store.count == 1)
        #expect(await store.entry(id: a.id)?.exportURL == export)
    }

    /// "Save overwrites the previous export" survives a relaunch, through the
    /// ShotzCore protocol the editor will use.
    @Test func exportURLPersistsAcrossReopenViaProtocol() async throws {
        defer { cleanup() }
        let a = try capture()
        let first: any HistoryStore = FileHistoryStore(paths: paths)
        await first.add(a)
        #expect(await first.exportURL(for: a.id) == nil)
        let export = paths.root.appending(path: "Exports/Shotz A.png")
        try FileManager.default.createDirectory(at: export.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: export)
        await first.markExported(id: a.id, url: export)

        let reopened: any HistoryStore = FileHistoryStore(paths: paths)
        #expect(await reopened.exportURL(for: a.id) == export)
        // A later export replaces it.
        let second = paths.root.appending(path: "Exports/Shotz A 2.png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: second)
        await reopened.markExported(id: a.id, url: second)
        #expect(await FileHistoryStore(paths: paths).exportURL(for: a.id) == second)
        // Gone from disk: nil, so the editor makes a fresh export.
        try FileManager.default.removeItem(at: second)
        #expect(await reopened.exportURL(for: a.id) == nil)
        // Unknown capture: nil, and marking it is a no-op.
        await reopened.markExported(id: UUID(), url: export)
        #expect(await reopened.exportURL(for: UUID()) == nil)
    }

    /// The exact closure types `EditorCoordinator(previousExport:recordExport:)`
    /// takes, built the way AppCoordinator builds them.
    @Test func editorExportHooksRoundTrip() async throws {
        defer { cleanup() }
        let history = FileHistoryStore(paths: paths)
        let previousExport: @Sendable (CaptureResult.ID) async -> URL? = { await history.exportURL(for: $0) }
        let recordExport: @Sendable (CaptureResult.ID, URL) async -> Void = { await history.markExported(id: $0, url: $1) }
        let a = try capture()
        await history.add(a)
        #expect(await previousExport(a.id) == nil)
        let export = paths.root.appending(path: "Shotz A.png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: export)
        await recordExport(a.id, export)
        #expect(await previousExport(a.id) == export)
        let reopened = FileHistoryStore(paths: paths)
        let previousAfterReopen: @Sendable (CaptureResult.ID) async -> URL? = { await reopened.exportURL(for: $0) }
        #expect(await previousAfterReopen(a.id) == export)
    }

    // MARK: --debug-edit-capture reuse

    @Test func debugCaptureIDIsStablePerSourcePath() {
        let a = URL(filePath: "/tmp/shotz-samples/a.png")
        #expect(DebugCaptureIdentity.id(forSourcePath: a) == DebugCaptureIdentity.id(forSourcePath: a))
        #expect(DebugCaptureIdentity.id(forSourcePath: URL(filePath: "/tmp/shotz-samples/./x/../a.png"))
            == DebugCaptureIdentity.id(forSourcePath: a))
        #expect(DebugCaptureIdentity.id(forSourcePath: URL(filePath: "/tmp/shotz-samples/b.png"))
            != DebugCaptureIdentity.id(forSourcePath: a))
        let id = DebugCaptureIdentity.id(forSourcePath: a).uuidString
        #expect(Array(id)[14] == "5")   // name-based UUID layout
    }

    /// Second launch with the same source: the existing entry is reused; once
    /// its image is gone it is imported again under the same id.
    @Test func reusableCaptureFollowsHistoryAndFile() async throws {
        defer { cleanup() }
        let source = URL(filePath: "/tmp/shotz-samples/a.png")
        let id = DebugCaptureIdentity.id(forSourcePath: source)
        let store = FileHistoryStore(paths: paths)
        #expect(await store.reusableCapture(id: id) == nil)          // first launch: import

        try paths.createDirectories()
        let file = paths.captures.appending(path: "Shotz A.png")
        try FakeCaptureEngine.writePNG(width: 4, height: 3, to: file)
        let imported = CaptureResult(id: id, fileURL: file, displayName: "Shotz A", kind: .area,
                                     pixelSize: CGSize(width: 4, height: 3), scale: 2, displayID: 1)
        await store.add(imported)

        let secondLaunch = FileHistoryStore(paths: paths)            // a new process
        #expect(await secondLaunch.reusableCapture(id: id)?.fileURL == file)
        #expect(await secondLaunch.count == 1)

        try FileManager.default.removeItem(at: file)
        #expect(await secondLaunch.reusableCapture(id: id) == nil)   // re-import, same id
    }

    @Test func orderIsByCreationDateNotInsertion() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let old = try capture(age: 100), new = try capture(age: 1)
        await store.add(new)
        await store.add(old)
        #expect(await store.recent(limit: 10).map(\.id) == [new.id, old.id])
    }

    @Test func rapidConcurrentAddsAreAllKept() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let captures = try (0..<50).map { try capture(age: Double($0)) }
        await withTaskGroup(of: Void.self) { group in
            for c in captures { group.addTask { await store.add(c) } }
        }
        #expect(await store.count == 50)
        let reloaded = FileHistoryStore(paths: paths)
        #expect(await reloaded.recent(limit: 100).map(\.id) == captures.map(\.id))
    }

    @Test func concurrentAddsAndRemovesStayConsistent() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let captures = try (0..<30).map { try capture(age: Double($0)) }
        for c in captures { await store.add(c) }
        await withTaskGroup(of: Void.self) { group in
            for (i, c) in captures.enumerated() where i.isMultiple(of: 2) {
                group.addTask { await store.remove(id: c.id, deleteFile: true) }
            }
        }
        let expected = captures.enumerated().filter { !$0.offset.isMultiple(of: 2) }.map(\.element.id)
        #expect(await FileHistoryStore(paths: paths).recent(limit: 100).map(\.id) == expected)
    }

    @Test func pruneDropsExpiredAndTheirFiles() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let old = try capture(age: 10 * 86_400), fresh = try capture()
        await store.add(old)
        await store.add(fresh)
        try Data("{}".utf8).write(to: store.documentURL(for: old.id))
        #expect(await store.prune(olderThan: 86_400) == 1)
        #expect(await store.recent(limit: 10).map(\.id) == [fresh.id])
        #expect(!exists(old.fileURL))
        #expect(!exists(store.documentURL(for: old.id)))
        #expect(exists(fresh.fileURL))
    }

    @Test func pruneByRetention() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let twoDays = try capture(age: 2 * 86_400), tenDays = try capture(age: 10 * 86_400),
            fortyDays = try capture(age: 40 * 86_400), now = try capture()
        for c in [twoDays, tenDays, fortyDays, now] { await store.add(c) }
        #expect(await store.prune(retention: .forever) == 0)
        #expect(await store.count == 4)
        #expect(await store.prune(retention: .month) == 1)
        #expect(await store.prune(retention: .week) == 1)
        #expect(await store.prune(retention: .day) == 1)
        #expect(await store.recent(limit: 10).map(\.id) == [now.id])
    }

    @Test func missingFilesAreSkippedThenPruned() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture(age: 5), b = try capture()
        await store.add(a)
        await store.add(b)
        try Data("{}".utf8).write(to: store.documentURL(for: b.id))
        try FileManager.default.removeItem(at: b.fileURL)
        #expect(await store.recent(limit: 10).map(\.id) == [a.id])
        #expect(await store.count == 2)
        #expect(await store.prune(retention: .forever) == 1)
        #expect(await store.count == 1)
        #expect(!exists(store.documentURL(for: b.id)))
    }

    @Test func corruptIndexIsMovedAsideAndRebuiltFromCaptures() async throws {
        defer { cleanup() }
        let a = try capture(name: "Shotz A"), b = try capture(name: "Shotz B")
        try Data("this is not json".utf8).write(to: paths.historyIndex)
        let store = FileHistoryStore(paths: paths)
        let recent = await store.recent(limit: 10)
        #expect(Set(recent.map(\.displayName)) == ["Shotz A", "Shotz B"])
        #expect(recent.allSatisfy { $0.pixelSize == CGSize(width: 4, height: 3) })
        let aside = try FileManager.default.contentsOfDirectory(atPath: paths.root.path(percentEncoded: false))
            .filter { $0.hasPrefix("history.corrupt-") }
        #expect(aside.count == 1)
        // The rebuilt index was written and is readable.
        #expect(await FileHistoryStore(paths: paths).count == 2)
        _ = (a, b)
    }

    @Test func badEntryDoesNotLoseTheRest() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture()
        await store.add(a)
        // Splice a malformed entry into the saved index.
        var json = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.historyIndex)) as? [String: Any] ?? [:]
        var entries = json["entries"] as? [Any] ?? []
        entries.append(["capture": ["id": "not-a-uuid"]])
        json["entries"] = entries
        try JSONSerialization.data(withJSONObject: json).write(to: paths.historyIndex)
        #expect(await FileHistoryStore(paths: paths).recent(limit: 10).map(\.id) == [a.id])
    }

    @Test func legacyArrayIndexIsMigrated() async throws {
        defer { cleanup() }
        let a = try capture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([a]).write(to: paths.historyIndex)
        let store = FileHistoryStore(paths: paths)
        #expect(await store.recent(limit: 10).map(\.id) == [a.id])
        await store.markExported(id: a.id, url: URL(filePath: "/tmp/x.png"))
        let raw = try JSONSerialization.jsonObject(with: Data(contentsOf: paths.historyIndex)) as? [String: Any]
        #expect(raw?["version"] as? Int == 1)
    }

    @Test func missingIndexStartsEmpty() async {
        defer { cleanup() }
        #expect(await FileHistoryStore(paths: paths).recent(limit: 10).isEmpty)
    }

    @Test func clearRemovesEverythingInsideShotzFoldersOnly() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture()
        await store.add(a)
        let orphan = paths.captures.appending(path: "orphan.png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: orphan)
        try Data("{}".utf8).write(to: store.documentURL(for: a.id))
        let outside = FileManager.default.temporaryDirectory.appending(path: "ShotzKeep-\(UUID().uuidString).png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        await store.markExported(id: a.id, url: outside)

        await store.clear()
        #expect(await store.count == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.captures.path(percentEncoded: false)).isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: paths.documents.path(percentEncoded: false)).isEmpty)
        #expect(exists(outside))
        #expect(await FileHistoryStore(paths: paths).count == 0)
    }

    @Test func removeNeverDeletesFilesOutsideCaptures() async throws {
        defer { cleanup() }
        let outside = FileManager.default.temporaryDirectory.appending(path: "ShotzOutside-\(UUID().uuidString).png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: outside)
        defer { try? FileManager.default.removeItem(at: outside) }
        let c = CaptureResult(fileURL: outside, displayName: "x", kind: .area, pixelSize: CGSize(width: 2, height: 2),
                              scale: 1, displayID: 1)
        let store = FileHistoryStore(paths: paths)
        await store.add(c)
        await store.remove(id: c.id, deleteFile: true)
        #expect(exists(outside))
    }

    // MARK: Two processes sharing one folder (two stores = two open files, so
    // they contend for the flock exactly like separate processes would).

    @Test func storesSeeEachOthersWritesAndNeverDropThem() async throws {
        defer { cleanup() }
        let app = FileHistoryStore(paths: paths), dev = FileHistoryStore(paths: paths)
        #expect(await dev.count == 0)          // dev has loaded (empty) first
        let a = try capture(age: 5)
        await app.add(a)
        #expect(await dev.recent(limit: 10).map(\.id) == [a.id])   // reloads the replaced file
        let b = try capture()
        await dev.add(b)
        #expect(await app.recent(limit: 10).map(\.id) == [b.id, a.id])
        #expect(await FileHistoryStore(paths: paths).count == 2)
    }

    @Test func staleCacheNeverResurrectsARemovedEntry() async throws {
        defer { cleanup() }
        let one = FileHistoryStore(paths: paths), two = FileHistoryStore(paths: paths)
        let a = try capture(age: 5), b = try capture()
        await one.add(a)
        await two.add(b)
        #expect(await two.count == 2)
        await one.remove(id: a.id, deleteFile: false)
        await two.markExported(id: b.id, url: URL(filePath: "/tmp/b.png"))   // two's cache still had `a`
        let fresh = FileHistoryStore(paths: paths)
        #expect(await fresh.recent(limit: 10).map(\.id) == [b.id])
        #expect(await fresh.entry(id: b.id)?.exportURL == URL(filePath: "/tmp/b.png"))
    }

    @Test func concurrentWritersInTwoStoresLoseNothing() async throws {
        defer { cleanup() }
        let one = FileHistoryStore(paths: paths), two = FileHistoryStore(paths: paths)
        let captures = try (0..<40).map { try capture(age: Double($0)) }
        await withTaskGroup(of: Void.self) { group in
            for (i, c) in captures.enumerated() {
                let store = i.isMultiple(of: 2) ? one : two
                group.addTask { await store.add(c) }
            }
        }
        #expect(await FileHistoryStore(paths: paths).recent(limit: 100).map(\.id) == captures.map(\.id))
        #expect(exists(paths.root.appending(path: "history.lock")))
    }

    @Test func foundationWriterInterleavingIsMigratedNotLost() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture(age: 5)
        await store.add(a)
        // Another (older) build rewrites the index as a bare array with its own entry.
        let b = try capture()
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode([b]).write(to: paths.historyIndex, options: .atomic)
        #expect(await store.recent(limit: 10).map(\.id) == [b.id])   // sees the other writer's file
        await store.add(a)
        #expect(Set(await FileHistoryStore(paths: paths).recent(limit: 10).map(\.id)) == [a.id, b.id])
    }

    // MARK: Dev profile isolation

    @Test func devProfileStoreNeverResolvesInsideTheRealFolder() {
        let real = ShotzPaths.forVariant(.production)
        let dev = ShotzPaths.forVariant(.development)
        let realRoot = real.root.standardizedFileURL.path(percentEncoded: false)
        let realPrefix = realRoot.hasSuffix("/") ? realRoot : realRoot + "/"
        let store = FileHistoryStore(paths: dev)
        let devURLs = [dev.root, dev.captures, dev.documents, dev.historyIndex, dev.temporary, dev.dragExports,
                       store.documentURL(for: UUID())]
        for url in devURLs {
            let path = url.standardizedFileURL.path(percentEncoded: false)
            #expect(!path.hasPrefix(realPrefix), "\(path) is inside \(realPrefix)")
            #expect(path != realRoot)
        }
        #expect(dev.historyIndex != real.historyIndex)
        #expect(dev.temporary != real.temporary)
        #expect(dev.root.path(percentEncoded: false).contains("/Application Support/ShotZ Dev"))
    }

    @Test func renderedPNGLivesNextToTheDocumentAndGoesWithTheCapture() async throws {
        defer { cleanup() }
        let store = FileHistoryStore(paths: paths)
        let a = try capture()
        await store.add(a)
        #expect(store.renderedURL(for: a.id).deletingLastPathComponent() == store.documentURL(for: a.id).deletingLastPathComponent())
        #expect(store.renderedURL(for: a.id).lastPathComponent == "\(a.id.uuidString).png")
        try Data("{}".utf8).write(to: store.documentURL(for: a.id))
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: store.renderedURL(for: a.id))
        await store.remove(id: a.id, deleteFile: true)
        #expect(!exists(store.renderedURL(for: a.id)))
        #expect(!exists(store.documentURL(for: a.id)))
    }

    @Test func documentURLPerID() {
        let id = UUID()
        let store = FileHistoryStore(paths: paths)
        #expect(store.documentURL(for: id).lastPathComponent == "\(id.uuidString).json")
        #expect(store.documentURL(for: id).deletingLastPathComponent().standardizedFileURL == paths.documents.standardizedFileURL)
        #expect(!store.hasDocument(for: id))
    }
}
