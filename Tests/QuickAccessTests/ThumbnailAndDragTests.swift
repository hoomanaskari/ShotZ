import AppKit
import Testing
@testable import QuickAccess
import ShotzCore

struct ThumbnailAndDragTests {
    @Test func thumbnailSizeFollowsCardInDevicePixels() {
        let card = CGSize(width: 250, height: 156)
        #expect(ThumbnailLoader.maxPixelSize(pixelSize: CGSize(width: 5120, height: 2880), cardSize: card, scale: 2) == 500)
        // Tall: height-limited.
        #expect(ThumbnailLoader.maxPixelSize(pixelSize: CGSize(width: 800, height: 2400), cardSize: card, scale: 2) == 312)
        // Never upsample a small capture.
        #expect(ThumbnailLoader.maxPixelSize(pixelSize: CGSize(width: 100, height: 60), cardSize: card, scale: 2) == 100)
    }

    @Test func thumbnailIsDownsampled() async throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "thumb-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) } // test scratch
        try FakeCaptureEngine.writePNG(width: 2000, height: 1000, to: url)
        let image = try #require(await ThumbnailLoader.load(url: url, maxPixelSize: 400))
        #expect(image.width == 400)
        #expect(image.height == 200)
    }

    @Test @MainActor func dragWriterOffersFileAndImage() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "Drag Name \(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) } // test scratch
        try FakeCaptureEngine.writePNG(width: 20, height: 10, to: url)
        let writer = DragFileWriter(fileURL: url)
        let pb = NSPasteboard(name: NSPasteboard.Name("shotz-test-\(UUID().uuidString)"))
        defer { pb.releaseGlobally() }
        pb.clearContents()
        #expect(pb.writeObjects([writer]))
        let urls = pb.readObjects(forClasses: [NSURL.self]) as? [URL]
        #expect(urls == [url])
        let data = try #require(pb.data(forType: .png))
        #expect(data == (try Data(contentsOf: url)))
    }
}
