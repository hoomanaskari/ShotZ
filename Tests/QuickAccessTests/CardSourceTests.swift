import CoreGraphics
import Foundation
import Testing
@testable import QuickAccess
import ShotzCore

struct CardSourceTests {
    let capture = CaptureResult(
        fileURL: URL(filePath: "/captures/Shotz 1.png"), displayName: "Shotz 1", kind: .area,
        pixelSize: CGSize(width: 1920, height: 1080), scale: 2, displayID: 1
    )

    @Test func plainCaptureDeliversItsOwnFile() {
        let s = CardSource(capture: capture, imageURL: nil) { _ in nil }
        #expect(s.fileURL == capture.fileURL)
        #expect(s.pixelSize == capture.pixelSize)
        #expect(s.caption == "1920 × 1080")
        #expect(s.exportName == "Shotz 1")
        #expect(!s.isAnnotated)
    }

    @Test func annotatedCardDeliversTheFlattenedImage() {
        let annotated = URL(filePath: "/tmp/annotated.png")
        let s = CardSource(capture: capture, imageURL: annotated) { $0 == annotated ? CGSize(width: 2200, height: 1400) : nil }
        #expect(s.fileURL == annotated)
        #expect(s.pixelSize == CGSize(width: 2200, height: 1400)) // background padding grew it
        #expect(s.caption == "2200 × 1400")
        #expect(s.exportName == "Shotz 1") // export name stays the capture's
        #expect(s.capture == capture)      // Annotate reopens the original
        #expect(s.isAnnotated)
    }

    @Test func unreadableAnnotatedImageFallsBackToCaptureSize() {
        let s = CardSource(capture: capture, imageURL: URL(filePath: "/nope.png")) { _ in nil }
        #expect(s.pixelSize == capture.pixelSize)
        #expect(s.fileURL == URL(filePath: "/nope.png"))
    }

    @Test func headerPixelSizeReadsRealFiles() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "src-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) } // test scratch
        try FakeCaptureEngine.writePNG(width: 31, height: 17, to: url)
        #expect(CardSource.headerPixelSize(url) == CGSize(width: 31, height: 17))
    }
}
