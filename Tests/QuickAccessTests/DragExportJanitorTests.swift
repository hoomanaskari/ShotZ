import Foundation
import Testing
@testable import QuickAccess

final class DragExportJanitorTests {
    let root = FileManager.default.temporaryDirectory.appending(path: "ShotzDragTests-\(UUID().uuidString)", directoryHint: .isDirectory)

    deinit { try? FileManager.default.removeItem(at: root) } // test scratch only

    func makeDrag(age: TimeInterval) throws -> URL {
        let folder = root.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appending(path: "Shotz test.png")
        try Data([1, 2, 3]).write(to: file)
        let date = Date().addingTimeInterval(-age)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: folder.path)
        return file
    }

    @Test func purgesOnlyOldFolders() throws {
        let old = try makeDrag(age: 2 * 86_400)
        let fresh = try makeDrag(age: 60)
        #expect(DragExportJanitor.purge(root: root) == 1)
        #expect(!FileManager.default.fileExists(atPath: old.deletingLastPathComponent().path))
        #expect(FileManager.default.fileExists(atPath: fresh.path))
    }

    @Test func missingRootIsFine() {
        #expect(DragExportJanitor.purge(root: root.appending(path: "nope")) == 0)
    }

    @Test func dragFolderOnlyDirectlyUnderRoot() throws {
        let file = try makeDrag(age: 0)
        #expect(DragExportJanitor.dragFolder(of: file, root: root) == file.deletingLastPathComponent().standardizedFileURL)
        #expect(DragExportJanitor.dragFolder(of: URL(filePath: "/tmp/x/y.png"), root: root) == nil)
        #expect(DragExportJanitor.dragFolder(of: root.appending(path: "loose.png"), root: root) == nil)
    }

    @Test func cancelledDragFolderRemovedAfterDelay() async throws {
        let file = try makeDrag(age: 0)
        DragExportJanitor.removeLater(file: file, root: root, delay: .milliseconds(100))
        #expect(FileManager.default.fileExists(atPath: file.path))
        try await Task.sleep(for: .milliseconds(500))
        #expect(!FileManager.default.fileExists(atPath: file.deletingLastPathComponent().path))
    }
}
