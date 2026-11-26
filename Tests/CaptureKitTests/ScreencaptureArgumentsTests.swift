import Foundation
import Testing
@testable import CaptureKit
import ShotzCore

struct ScreencaptureArgumentsTests {
    let out = "/tmp/out.png"

    func args(_ mode: CaptureMode, shadow: Bool = true, sound: Bool = true, display: Int = 1) -> [String] {
        let options = CaptureOptions(includeWindowShadow: shadow, playSound: sound, destinationDirectory: URL(filePath: "/tmp"))
        return ScreencaptureArguments.make(mode: mode, options: options, displayNumber: display, outputPath: out)
    }

    @Test func modes() {
        #expect(args(.area) == ["-i", "-t", "png", out])
        #expect(args(.window) == ["-i", "-W", "-t", "png", out])
        #expect(args(.allInOne) == ["-i", "-U", "-t", "png", out])
        #expect(args(.fullscreen, display: 2) == ["-D", "2", "-t", "png", out])
    }

    @Test func shadowAndSound() {
        #expect(args(.window, shadow: false, sound: false) == ["-i", "-W", "-o", "-x", "-t", "png", out])
    }

    @Test func displayNumbering() {
        #expect(DisplayLocator.number(of: 5, in: [3, 5, 9], main: 5) == 1)
        #expect(DisplayLocator.number(of: 3, in: [3, 5, 9], main: 5) == 2)
        #expect(DisplayLocator.number(of: 9, in: [3, 5, 9], main: 5) == 3)
        #expect(DisplayLocator.number(of: 42, in: [3, 5], main: 5) == 1)
    }

    @Test func imageInfoReadsHeader() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "info-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: url) }
        try FakeCaptureEngine.writePNG(width: 12, height: 7, to: url)
        let info = try #require(ImageInfo(url: url))
        #expect(info.pixelSize == CGSize(width: 12, height: 7))
        #expect(info.scale == 1)
    }
}
