import AnnotationKit
import AppKit
import Foundation
import ImageIO
import ShotzCore
import Testing
@testable import AnnotationEditor

/// Closing a capture's editor hands it back with the annotated result (SPEC §4.6).
extension EditorUITests {
@MainActor
@Suite struct EditorCloseTests {
    /// A stand-in for AppCoordinator.
    private final class Box: AnnotationEditingDelegate {
        var calls: [(CaptureResult, URL?, UInt32?)] = []
        func editor(didClose capture: CaptureResult, renderedImageURL: URL?, onDisplay displayID: UInt32?) {
            calls.append((capture, renderedImageURL, displayID))
        }
    }

    private struct Fixture {
        let dir: URL
        let coordinator: EditorCoordinator
        let capture: CaptureResult
        let rendered: URL
        let box: Box // retained here: the coordinator's delegate is weak
    }

    private func fixture() throws -> Fixture {
        _ = NSApplication.shared
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShotzEditorClose-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ctx = try #require(CGContext(data: nil, width: 160, height: 100, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 160, height: 100))
        let png = dir.appending(path: "capture.png")
        let dest = try #require(CGImageDestinationCreateWithURL(png as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, try #require(ctx.makeImage()), nil)
        #expect(CGImageDestinationFinalize(dest))
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        let rendered = dir.appending(path: "rendered.png")
        let coordinator = EditorCoordinator(settings: SettingsStore(defaults: defaults), exporter: DefaultExportService(),
                                            documentURL: { dir.appending(path: "\($0.uuidString).json") },
                                            renderedURL: { _ in rendered })
        coordinator.presentsWindows = false
        let box = Box()
        coordinator.delegate = box
        let capture = CaptureResult(fileURL: png, displayName: "Test capture", kind: .area,
                                    pixelSize: CGSize(width: 160, height: 100), scale: 1, displayID: 1)
        return Fixture(dir: dir, coordinator: coordinator, capture: capture, rendered: rendered, box: box)
    }

    private func waitForCalls(_ box: Box, _ count: Int) async {
        for _ in 0..<100 where box.calls.count < count { try? await Task.sleep(for: .milliseconds(20)) }
    }

    private func open(_ f: Fixture) throws -> EditorWindowController {
        f.coordinator.openEditor(for: f.capture)
        return try #require(f.coordinator.controller(for: f.capture.id))
    }

    private let box = AnnotationObject(shape: .rectangle(CGRect(x: 20, y: 20, width: 60, height: 40), cornerRadius: 0),
                                       style: ObjectStyle(lineWidth: 3))

    @Test func editsRenderTheFlattenedImageBeforeTheHandBack() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let c = try open(f)
        c.store.perform("Add") { $0.objects.append(box) }
        let document = c.store.document
        c.window?.close()
        #expect(!f.coordinator.isOpen(f.capture.id))
        await waitForCalls(f.box, 1)
        let call = try #require(f.box.calls.first)
        #expect(call.0.id == f.capture.id)
        #expect(call.1 == f.rendered)
        // The file exists when the hand-back arrives and matches the export at full resolution.
        let written = try Data(contentsOf: f.rendered)
        let expected = try DocumentExport.data(document, base: BaseImageProvider(url: f.capture.fileURL), format: .png, quality: 1, scale: 1)
        #expect(written == expected)
        let src = try #require(CGImageSourceCreateWithURL(f.rendered as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 160)
    }

    @Test func noEditsHandsBackNilAndRemovesAStaleRender() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        try Data("stale".utf8).write(to: f.rendered)
        let c = try open(f)
        c.window?.close()
        await waitForCalls(f.box, 1)
        #expect(f.box.calls.count == 1)
        #expect(f.box.calls.first?.1 == nil)
        #expect(!FileManager.default.fileExists(atPath: f.rendered.path(percentEncoded: false)))
    }

    @Test func reopeningRestoresTheDocumentAndCloseUpdatesTheRender() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        var c = try open(f)
        c.store.perform("Add") { $0.objects.append(box) }
        c.window?.close()
        await waitForCalls(f.box, 1)
        let first = try Data(contentsOf: f.rendered)

        c = try open(f)
        #expect(c.store.document.objects.map(\.id) == [box.id]) // editable document restored
        c.store.perform("Crop") { $0.crop = CGRect(x: 0, y: 0, width: 100, height: 80) }
        c.window?.close()
        await waitForCalls(f.box, 2)
        #expect(f.box.calls.count == 2)
        let second = try Data(contentsOf: f.rendered)
        #expect(second != first)
        let src = try #require(CGImageSourceCreateWithURL(f.rendered as CFURL, nil))
        let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
        #expect(props[kCGImagePropertyPixelWidth] as? Int == 100) // the annotated (cropped) size
    }

    @Test func quittingSavesButDoesNotHandBack() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let c = try open(f)
        c.store.perform("Add") { $0.objects.append(box) }
        c.isTerminating = true
        c.window?.close()
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.box.calls.isEmpty)
        let saved = try AnnotationDocument.load(from: f.dir.appending(path: "\(f.capture.id.uuidString).json"))
        #expect(saved.objects.count == 1)
    }

    @Test func fileOpenedImagesNeverHandBack() async throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        f.coordinator.openEditor(imageAt: f.capture.fileURL)
        #expect(f.coordinator.openWindowCount == 1)
        // Close only this test's window: other suites run alongside and own theirs.
        f.coordinator.controller(forFile: f.capture.fileURL)?.window?.close()
        #expect(f.coordinator.openWindowCount == 0)
        try await Task.sleep(for: .milliseconds(300))
        #expect(f.box.calls.isEmpty)
    }

    @Test func openingAnOpenCaptureReusesItsWindow() throws {
        let f = try fixture()
        defer { try? FileManager.default.removeItem(at: f.dir) } // best-effort cleanup
        let c = try open(f)
        f.coordinator.openEditor(for: f.capture)
        #expect(f.coordinator.controller(for: f.capture.id) === c)
        #expect(f.coordinator.openWindowCount == 1)
        c.isTerminating = true
        c.window?.close()
    }
}
}
