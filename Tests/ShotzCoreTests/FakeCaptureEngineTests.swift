import Foundation
import Testing
@testable import ShotzCore

struct FakeCaptureEngineTests {
    @Test func scriptedOutcomes() async throws {
        let dir = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: dir) }
        let engine = FakeCaptureEngine(outcomes: [.image(width: 10, height: 5), .cancel, .fail(.permissionDenied)])
        let options = CaptureOptions(destinationDirectory: dir)

        let result = try #require(try await engine.capture(.fullscreen, options: options))
        #expect(result.kind == .fullscreen)
        #expect(result.pixelSize == CGSize(width: 10, height: 5))
        #expect(FileManager.default.fileExists(atPath: result.fileURL.path(percentEncoded: false)))
        #expect(result.displayName.hasPrefix("ShotZ "))

        #expect(try await engine.capture(.area, options: options) == nil)
        await #expect(throws: CaptureError.permissionDenied) {
            try await engine.capture(.area, options: options)
        }
        #expect(await engine.requestedModes == [.fullscreen, .area, .area])
    }

    @Test func captureResultCodable() throws {
        let r = CaptureResult(
            fileURL: URL(filePath: "/tmp/a.png"), displayName: "a", kind: .window,
            pixelSize: CGSize(width: 3, height: 4), scale: 2, displayID: 7
        )
        let data = try JSONEncoder().encode(r)
        #expect(try JSONDecoder().decode(CaptureResult.self, from: data) == r)
    }

    @Test func paths() {
        let p = ShotzPaths(root: URL(filePath: "/x/Shotz", directoryHint: .isDirectory))
        #expect(p.captures.path(percentEncoded: false).hasSuffix("/x/Shotz/Captures/"))
        #expect(ShotzPaths.default.root.path(percentEncoded: false).hasSuffix("Library/Application Support/com.pixelforty.shotz/"))
    }
}
