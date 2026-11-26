import CoreGraphics
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
