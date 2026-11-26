import Foundation
import ImageIO
import Testing
@testable import ShotzCore

struct ExportServiceTests {
    @Test func savesWithCollisionSafeNames() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.png")
        try FakeCaptureEngine.writePNG(width: 8, height: 6, to: source)
        let exportDir = dir.appending(path: "Export", directoryHint: .isDirectory)
        let service = DefaultExportService(
            paths: ShotzPaths(root: dir.appending(path: "root")),
            configuration: { ExportConfiguration(exportFolder: exportDir) }
        )
        let a = try await service.saveToExportFolder(imageAt: source, suggestedName: "Shot", askDestination: false)
        let b = try await service.saveToExportFolder(imageAt: source, suggestedName: "Shot", askDestination: false)
        #expect(a?.lastPathComponent == "Shot.png")
        #expect(b?.lastPathComponent == "Shot 2.png")
        #expect(try Data(contentsOf: try #require(a)) == Data(contentsOf: source))
    }

    @Test func transcodesToJPEGAndDownscales() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.png")
        try FakeCaptureEngine.writePNG(width: 20, height: 10, to: source)
        let service = DefaultExportService(
            paths: ShotzPaths(root: dir),
            configuration: { ExportConfiguration(exportFolder: dir, format: .jpeg) }
        )
        let url = try #require(try await service.saveToExportFolder(imageAt: source, suggestedName: "J", askDestination: false))
        #expect(url.pathExtension == "jpg")
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
        #expect(CGImageSourceGetType(src) as String? == "public.jpeg")
    }

    @Test func dragExportUsesExactName() throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = dir.appending(path: "src.png")
        try FakeCaptureEngine.writePNG(width: 4, height: 4, to: source)
        let service = DefaultExportService(paths: ShotzPaths(root: dir), configuration: { ExportConfiguration(exportFolder: dir) })
        let first = try service.exportFileURLForDrag(imageAt: source, suggestedName: "Drag Me")
        let second = try service.exportFileURLForDrag(imageAt: source, suggestedName: "Drag Me")
        #expect(first.lastPathComponent == "Drag Me.png")
        #expect(second.lastPathComponent == "Drag Me.png")
        #expect(first != second)
        #expect(FileManager.default.fileExists(atPath: first.path(percentEncoded: false)))
    }
}
