import AnnotationKit
import CoreGraphics
import Foundation
import ImageIO
import ShotzCore
import Testing
@testable import AnnotationEditor

/// Stand-in for the history store's export path.
private actor FakeHistory {
    var paths: [CaptureResult.ID: URL] = [:]
    var records = 0
    func previous(_ id: CaptureResult.ID) -> URL? { paths[id] }
    func record(_ id: CaptureResult.ID, _ url: URL) { paths[id] = url; records += 1 }
}

/// Writes "exports" into a folder, numbering names like the real service.
private struct FakeExportService: ExportService {
    let folder: URL
    func copyToPasteboard(imageAt url: URL) async throws {}
    func saveToExportFolder(imageAt url: URL, suggestedName: String, askDestination: Bool) async throws -> URL? {
        var n = 1
        var dest = folder.appending(path: "\(suggestedName).png")
        while FileManager.default.fileExists(atPath: dest.path(percentEncoded: false)) {
            n += 1
            dest = folder.appending(path: "\(suggestedName) \(n).png")
        }
        try FileManager.default.copyItem(at: url, to: dest)
        return dest
    }
    func exportFileURLForDrag(imageAt url: URL, suggestedName: String) throws -> URL { url }
}

@MainActor
struct ExportRecordTests {
    private struct Fixture {
        let dir: URL
        let document: AnnotationDocument
        let base: BaseImageProvider
        let settings: SettingsStore
        let service: FakeExportService
    }

    private func fixture() throws -> Fixture {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShotzEditorExport-\(UUID().uuidString)")
        let exports = dir.appending(path: "Exports")
        try FileManager.default.createDirectory(at: exports, withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: 120, height: 80, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 120, height: 80))
        let image = try #require(ctx.makeImage())
        let baseURL = dir.appending(path: "capture.png")
        let dest = try #require(CGImageDestinationCreateWithURL(baseURL as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        #expect(CGImageDestinationFinalize(dest))
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        return Fixture(
            dir: dir,
            document: AnnotationDocument(baseImageURL: baseURL, pixelSize: CGSize(width: 120, height: 80)),
            base: BaseImageProvider(url: baseURL),
            settings: SettingsStore(defaults: defaults),
            service: FakeExportService(folder: exports)
        )
    }

    private func exporter(_ f: Fixture, history: FakeHistory, id: UUID) -> EditorExporter {
        let record = ExportRecord(captureID: id,
                                  previous: { await history.previous($0) },
                                  record: { await history.record($0, $1) })
        return EditorExporter(exporter: f.service, settings: f.settings, base: f.base, record: record)
    }

    @Test func saveExportsRecordsAndOverwritesAfterReopening() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let history = FakeHistory()
        let id = UUID()

        // First Save: a normal export, recorded with the capture.
        let first = try #require(try await exporter(f, history: history, id: id).save(f.document, name: "Shot"))
        #expect(await history.previous(id) == first)

        // "Reopen": a new window's exporter, same capture. Save overwrites the recorded file.
        var edited = f.document
        edited.objects = [AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 30), cornerRadius: 0))]
        let before = try Data(contentsOf: first)
        let second = try #require(try await exporter(f, history: history, id: id).save(edited, name: "Shot"))
        #expect(second == first)
        #expect(try Data(contentsOf: second) != before)
        let files = try FileManager.default.contentsOfDirectory(atPath: f.service.folder.path(percentEncoded: false))
        #expect(files == ["Shot.png"]) // no "Shot 2.png"
        #expect(await history.records == 2)
    }

    @Test func missingPreviousExportFallsBackToANormalExport() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let history = FakeHistory()
        let id = UUID()
        let gone = f.dir.appending(path: "Moved Away/Shot.png")
        await history.record(id, gone)
        let saved = try #require(try await exporter(f, history: history, id: id).save(f.document, name: "Shot"))
        #expect(saved != gone)
        #expect(FileManager.default.fileExists(atPath: saved.path(percentEncoded: false)))
        #expect(await history.previous(id) == saved) // the new file is recorded
    }

    @Test func overwriteKeepsTheFileFormatOfItsExtension() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let history = FakeHistory()
        let id = UUID()
        let jpeg = f.service.folder.appending(path: "Shot.jpg")
        try Data("old".utf8).write(to: jpeg)
        await history.record(id, jpeg)
        let saved = try #require(try await exporter(f, history: history, id: id).save(f.document, name: "Shot"))
        #expect(saved == jpeg)
        let src = try #require(CGImageSourceCreateWithURL(jpeg as CFURL, nil))
        #expect(CGImageSourceGetType(src) as String? == "public.jpeg")
    }

    @Test func imagesOpenedFromFilesKeepTheInWindowBehaviour() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let exporter = EditorExporter(exporter: f.service, settings: f.settings, base: f.base)
        let first = try #require(try await exporter.save(f.document, name: "File"))
        let second = try #require(try await exporter.save(f.document, name: "File"))
        #expect(first == second)
        // A new window (no record) exports anew.
        let other = try #require(try await EditorExporter(exporter: f.service, settings: f.settings, base: f.base).save(f.document, name: "File"))
        #expect(other != first)
    }
}
