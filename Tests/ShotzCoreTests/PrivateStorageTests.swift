import Darwin
import Foundation
import Testing
@testable import ShotzCore

/// ShotZ's own storage is owner-only (folders 0700, files 0600); user exports keep normal modes.
struct PrivateStorageTests {
    let base: URL
    init() { base = FileManager.default.temporaryDirectory.appending(path: "ShotzPermTests-\(UUID().uuidString)", directoryHint: .isDirectory) }
    func cleanup() { try? FileManager.default.removeItem(at: base) }
    func mode(_ url: URL) -> mode_t? { PrivateStorage.mode(of: url) }

    @Test func foldersAreCreatedAndTightenedTo0700() throws {
        defer { cleanup() }
        let nested = base.appending(path: "a/b/c", directoryHint: .isDirectory)
        try PrivateStorage.makeDirectory(nested)
        #expect(mode(nested) == 0o700)
        #expect(mode(base.appending(path: "a/b")) == 0o700)   // created parents too
        let existing = base.appending(path: "old", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try PrivateStorage.makeDirectory(existing)
        #expect(mode(existing) == 0o700)
    }

    @Test func atomicWritesStay0600() throws {
        defer { cleanup() }
        try PrivateStorage.makeDirectory(base)
        let file = base.appending(path: "history.json")
        try PrivateStorage.write(Data("1".utf8), to: file)
        #expect(mode(file) == 0o600)
        try PrivateStorage.write(Data("2".utf8), to: file)   // a new inode each time
        #expect(mode(file) == 0o600)
        // Foundation's atomic write keeps an existing file's mode, but a new file gets the
        // default (umask) mode: that is why callers protect after writing.
        try Data("3".utf8).write(to: file, options: .atomic)
        #expect(mode(file) == 0o600)
        let fresh = base.appending(path: "new.json")
        try Data("4".utf8).write(to: fresh, options: .atomic)
        #expect(mode(fresh) != 0o600)
        PrivateStorage.protectFile(fresh)
        #expect(mode(fresh) == 0o600)
    }

    @Test func pathsCreateOwnerOnlyFolders() throws {
        defer { cleanup() }
        let paths = ShotzPaths(root: base.appending(path: "data", directoryHint: .isDirectory))
        try paths.createDirectories()
        for dir in [paths.root, paths.captures, paths.documents] { #expect(mode(dir) == 0o700, "\(dir.lastPathComponent)") }
    }

    @Test func repairTightensATreeButNeverFollowsLinks() throws {
        defer { cleanup() }
        let fm = FileManager.default
        let root = base.appending(path: "data", directoryHint: .isDirectory)
        let outside = base.appending(path: "outside", directoryHint: .isDirectory)
        try fm.createDirectory(at: root.appending(path: "Captures"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        try fm.createDirectory(at: outside, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let capture = root.appending(path: "Captures/a.png")
        let outsideFile = outside.appending(path: "keep.txt")
        try Data("x".utf8).write(to: capture)
        try Data("y".utf8).write(to: outsideFile)
        chmod(capture.path(percentEncoded: false), 0o644)
        chmod(outsideFile.path(percentEncoded: false), 0o644)
        try fm.createSymbolicLink(at: root.appending(path: "link-dir"), withDestinationURL: outside)
        try fm.createSymbolicLink(at: root.appending(path: "link-file"), withDestinationURL: outsideFile)

        let changed = PrivateStorage.repair(root: root)
        #expect(changed >= 3)
        #expect(mode(root) == 0o700)
        #expect(mode(root.appending(path: "Captures")) == 0o700)
        #expect(mode(capture) == 0o600)
        #expect(mode(outside) == 0o755)        // never followed
        #expect(mode(outsideFile) == 0o644)
        #expect(PrivateStorage.repair(root: root) == 0)   // second pass: nothing left to do
    }

    @Test func repairCanLeaveFilesAndIsBounded() throws {
        defer { cleanup() }
        let root = base.appending(path: "tmp", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root.appending(path: "Drag/x"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let file = root.appending(path: "Drag/x/export.png")
        try Data("x".utf8).write(to: file)
        chmod(file.path(percentEncoded: false), 0o644)
        PrivateStorage.repair(root: root, files: false)
        #expect(mode(root.appending(path: "Drag/x")) == 0o700)
        #expect(mode(file) == 0o644)          // temp exports keep normal modes
        for i in 0..<5 { try FileManager.default.createDirectory(at: root.appending(path: "many/\(i)"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755]) }
        PrivateStorage.repair(root: root, limit: 2)
        let still755 = (0..<5).filter { mode(root.appending(path: "many/\($0)")) == 0o755 }
        #expect(!still755.isEmpty)            // the limit stopped the walk
    }

    @Test func userExportsKeepNormalPermissions() async throws {
        defer { cleanup() }
        let paths = ShotzPaths(root: base.appending(path: "data", directoryHint: .isDirectory), scratchName: "ShotzPermTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: paths.temporary) }
        let userFolder = base.appending(path: "Desktop", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: userFolder, withIntermediateDirectories: true)
        let source = base.appending(path: "src.png")
        try FakeCaptureEngine.writePNG(width: 4, height: 3, to: source)
        let service = DefaultExportService(paths: paths) { ExportConfiguration(exportFolder: userFolder) }
        let saved = try #require(try await service.saveToExportFolder(imageAt: source, suggestedName: "Shot", askDestination: false))
        #expect(mode(saved) == 0o644 || mode(saved).map { $0 & 0o044 != 0 } == true)   // readable as usual
        let drag = try service.exportFileURLForDrag(imageAt: source, suggestedName: "Shot")
        #expect(mode(drag.deletingLastPathComponent()) == 0o700)   // its folder is private
        #expect(mode(drag).map { $0 & 0o044 != 0 } == true)       // the dragged copy is a normal file
    }
}
