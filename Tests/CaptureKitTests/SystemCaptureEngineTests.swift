import CoreGraphics
import ImageIO
import Foundation
import Testing
@testable import CaptureKit
import ShotzCore

/// Drives the real engine against small shell scripts standing in for
/// `/usr/sbin/screencapture` (real captures need Screen Recording permission).
final class SystemCaptureEngineTests {
    let root: URL
    let captures: URL
    let fixture: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.appending(path: "ShotzCaptureTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        captures = root.appending(path: "Captures", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        fixture = root.appending(path: "fixture.png")
        try FakeCaptureEngine.writePNG(width: 64, height: 40, to: fixture)
    }

    deinit { try? FileManager.default.removeItem(at: root) } // test scratch only

    /// Writes an executable script; `$OUT` is the output path (last argument).
    func tool(_ body: String) throws -> URL {
        let url = root.appending(path: "tool-\(UUID().uuidString).sh")
        let script = "#!/bin/sh\nfor OUT; do :; done\necho \"$@\" > \"\(root.path)/args.txt\"\n\(body)\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    func engine(_ toolURL: URL, permission: Bool = true, display: DisplayLocator.Located = .init(displayID: 7, number: 2)) -> SystemCaptureEngine {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        return SystemCaptureEngine(environment: .init(
            executable: toolURL,
            hasPermission: { permission },
            displayUnderPointer: { display },
            now: { date }
        ))
    }

    var options: CaptureOptions {
        CaptureOptions(includeWindowShadow: true, playSound: false, destinationDirectory: captures, fileNamePattern: "Test %Y")
    }

    func recordedArgs() throws -> String {
        try String(contentsOf: root.appending(path: "args.txt"), encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func visibleFiles() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: captures.path).filter { !$0.hasPrefix(".") }.sorted()
    }

    func incomingFiles() throws -> [String] {
        let dir = captures.appending(path: ".incoming").path
        return (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
    }

    @Test func successPlacesFileWithPatternName() async throws {
        let e = engine(try tool("cp \"\(fixture.path)\" \"$OUT\""))
        let result = try #require(try await e.capture(.fullscreen, options: options))
        #expect(result.fileURL.lastPathComponent == "Test 2027.png")
        #expect(result.displayName == "Test 2027")
        #expect(result.pixelSize == CGSize(width: 64, height: 40))
        #expect(result.kind == .fullscreen)
        #expect(result.displayID == 7)
        #expect(try visibleFiles() == ["Test 2027.png"])
        #expect(try incomingFiles().isEmpty)
        #expect(try recordedArgs().hasPrefix("-D 2 -x -t png "))
    }

    /// A PNG shaped like a window capture: rounded opaque body on a clear canvas
    /// (`margin` > 0 adds a shadow-like transparent border).
    static func writeWindowLikePNG(width: Int, height: Int, margin: CGFloat, to url: URL) throws {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { throw CaptureError.failed("ctx") }
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        let body = CGRect(x: 0, y: 0, width: width, height: height).insetBy(dx: margin, dy: margin)
        ctx.addPath(CGPath(roundedRect: body, cornerWidth: 20, cornerHeight: 20, transform: nil))
        ctx.setFillColor(CGColor(gray: 0.9, alpha: 1))
        ctx.fillPath()
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { throw CaptureError.failed("png") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.failed("finalize") }
    }

    @Test func areaCaptureWithAlphaChannelStaysArea() async throws {
        // Opaque edge to edge, but the PNG has an alpha channel.
        let e = engine(try tool("cp \"\(fixture.path)\" \"$OUT\""))
        let result = try #require(try await e.capture(.area, options: options))
        #expect(result.kind == .area)
    }

    @Test(arguments: [CGFloat(0), 40])
    func windowLikeCaptureInAreaModeIsWindow(margin: CGFloat) async throws {
        let window = root.appending(path: "window-\(Int(margin)).png")
        try Self.writeWindowLikePNG(width: 400, height: 300, margin: margin, to: window)
        let e = engine(try tool("cp \"\(window.path)\" \"$OUT\""))
        #expect(try #require(try await e.capture(.area, options: options)).kind == .window)
        #expect(try #require(try await e.capture(.allInOne, options: options)).kind == .window)
        // Fullscreen never turns into a window, whatever the pixels.
        #expect(try #require(try await e.capture(.fullscreen, options: options)).kind == .fullscreen)
    }

    @Test func shadowFlagReachesTheTool() async throws {
        let e = engine(try tool("cp \"\(fixture.path)\" \"$OUT\""))
        var opts = options
        opts.includeWindowShadow = false
        _ = try await e.capture(.window, options: opts)
        #expect(try recordedArgs().hasPrefix("-i -W -o -x -t png "))
        opts.includeWindowShadow = true
        _ = try await e.capture(.window, options: opts)
        #expect(try recordedArgs().hasPrefix("-i -W -x -t png "))
    }

    @Test func collisionAppendsCounter() async throws {
        let e = engine(try tool("cp \"\(fixture.path)\" \"$OUT\""))
        _ = try await e.capture(.area, options: options)
        let second = try #require(try await e.capture(.area, options: options))
        #expect(second.fileURL.lastPathComponent == "Test 2027 2.png")
        #expect(try visibleFiles() == ["Test 2027 2.png", "Test 2027.png"])
    }

    @Test func cancelReturnsNilAndLeavesNothing() async throws {
        let e = engine(try tool("exit 1"))
        let result = try await e.capture(.area, options: options)
        #expect(result == nil)
        #expect(try visibleFiles().isEmpty)
        #expect(try incomingFiles().isEmpty)
    }

    @Test func errorOutputMapsToFailed() async throws {
        let e = engine(try tool("echo 'could not create image' >&2; exit 1"))
        await #expect(throws: CaptureError.failed("could not create image")) {
            _ = try await e.capture(.area, options: options)
        }
    }

    @Test func errorWithoutPermissionMapsToPermissionDenied() async throws {
        let e = engine(try tool("echo 'nope' >&2; exit 1"), permission: false)
        await #expect(throws: CaptureError.permissionDenied) {
            _ = try await e.capture(.area, options: options)
        }
    }

    @Test func imageWithoutPermissionIsDiscarded() async throws {
        let e = engine(try tool("cp \"\(fixture.path)\" \"$OUT\""), permission: false)
        await #expect(throws: CaptureError.permissionDenied) {
            _ = try await e.capture(.fullscreen, options: options)
        }
        #expect(try visibleFiles().isEmpty)
        #expect(try incomingFiles().isEmpty)
    }

    @Test func unreadableOutputFails() async throws {
        let e = engine(try tool("echo garbage > \"$OUT\""))
        await #expect(throws: CaptureError.failed("Unreadable capture output")) {
            _ = try await e.capture(.area, options: options)
        }
        #expect(try incomingFiles().isEmpty)
    }

    @Test func missingToolFails() async throws {
        let e = engine(root.appending(path: "does-not-exist"))
        await #expect(throws: CaptureError.self) {
            _ = try await e.capture(.area, options: options)
        }
    }

    @Test func secondCaptureWhileRunningIsBusy() async throws {
        let e = engine(try tool("sleep 0.6; cp \"\(fixture.path)\" \"$OUT\""))
        let opts = options
        async let first = e.capture(.area, options: opts)
        try await Task.sleep(for: .milliseconds(150))
        await #expect(throws: CaptureError.busy) {
            _ = try await e.capture(.area, options: opts)
        }
        #expect(try await first != nil)
        // Free again afterwards.
        #expect(try await e.capture(.area, options: opts) != nil)
    }
}
