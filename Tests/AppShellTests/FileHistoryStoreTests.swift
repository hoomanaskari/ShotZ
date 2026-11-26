import Foundation
import Testing
@testable import AppShell
import ShotzCore

struct FileHistoryStoreTests {
    func capture(in paths: ShotzPaths, age: TimeInterval = 0) throws -> CaptureResult {
        try paths.createDirectories()
        let url = paths.captures.appending(path: "\(UUID().uuidString).png")
        try FakeCaptureEngine.writePNG(width: 2, height: 2, to: url)
        return CaptureResult(fileURL: url, displayName: "c", kind: .area, pixelSize: CGSize(width: 2, height: 2),
                             scale: 1, displayID: 1, createdAt: Date().addingTimeInterval(-age))
    }

    func makePaths() -> ShotzPaths {
        ShotzPaths(root: FileManager.default.temporaryDirectory.appending(path: "ShotzHistory-\(UUID().uuidString)", directoryHint: .isDirectory))
    }

    @Test func addRecentPersistRemove() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = FileHistoryStore(paths: paths)
        let a = try capture(in: paths), b = try capture(in: paths)
        await store.add(a)
        await store.add(b)
        #expect(await store.recent(limit: 10).map(\.id) == [b.id, a.id])
        #expect(await store.recent(limit: 1).map(\.id) == [b.id])

        let reloaded = FileHistoryStore(paths: paths)
        #expect(await reloaded.recent(limit: 10).map(\.id) == [b.id, a.id])

        await reloaded.remove(id: b.id, deleteFile: true)
        #expect(await reloaded.recent(limit: 10).map(\.id) == [a.id])
        #expect(!FileManager.default.fileExists(atPath: b.fileURL.path(percentEncoded: false)))
        await reloaded.remove(id: a.id, deleteFile: false)
        #expect(FileManager.default.fileExists(atPath: a.fileURL.path(percentEncoded: false)))
    }

    @Test func pruneDropsOld() async throws {
        let paths = makePaths()
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let store = FileHistoryStore(paths: paths)
        let old = try capture(in: paths, age: 10 * 86_400), fresh = try capture(in: paths)
        await store.add(old)
        await store.add(fresh)
        await store.prune(olderThan: 86_400)
        #expect(await store.recent(limit: 10).map(\.id) == [fresh.id])
        #expect(!FileManager.default.fileExists(atPath: old.fileURL.path(percentEncoded: false)))
    }

    @Test func documentURLPerID() {
        let paths = makePaths()
        let id = UUID()
        #expect(FileHistoryStore(paths: paths).documentURL(for: id).lastPathComponent == "\(id.uuidString).json")
    }
}
