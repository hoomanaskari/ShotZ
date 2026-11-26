import os
import CoreGraphics
import Foundation
import ShotzCore

/// Phase 1 engine: drives `/usr/sbin/screencapture` (ARCHITECTURE §3).
///
/// One capture at a time (`CaptureError.busy`). The tool writes into a hidden
/// incoming folder next to the captures; the finished PNG is then moved into
/// place under the settings file-name pattern, so a capture file is never seen
/// half-written.
public actor SystemCaptureEngine: CaptureEngine {
    /// Seams for tests: the tool, the permission check and the display lookup.
    struct Environment: Sendable {
        var executable: URL
        var hasPermission: @Sendable () -> Bool
        var displayUnderPointer: @Sendable () -> DisplayLocator.Located
        var now: @Sendable () -> Date

        static let live = Environment(
            executable: URL(filePath: "/usr/sbin/screencapture"),
            hasPermission: { CGPreflightScreenCaptureAccess() },
            displayUnderPointer: { DisplayLocator.displayUnderPointer() },
            now: { Date() }
        )
    }

    private let env: Environment
    private var isCapturing = false
    private let log = ShotzLog.logger("CaptureKit")

    public init() { self.init(environment: .live) }

    init(environment: Environment) { env = environment }

    public func capture(_ mode: CaptureMode, options: CaptureOptions) async throws -> CaptureResult? {
        guard !isCapturing else { throw CaptureError.busy }
        isCapturing = true
        defer { isCapturing = false }

        let fm = FileManager.default
        let incoming = options.destinationDirectory.appending(path: ".incoming", directoryHint: .isDirectory)
        do {
            try fm.createDirectory(at: incoming, withIntermediateDirectories: true)
        } catch {
            throw CaptureError.failed("Cannot create captures folder: \(error.localizedDescription)")
        }
        let temp = incoming.appending(path: "\(UUID().uuidString).png", directoryHint: .notDirectory)
        let tempPath = temp.path(percentEncoded: false)
        // Removes the temp file on every exit path except a successful move.
        defer { if fm.fileExists(atPath: tempPath) { try? fm.removeItem(at: temp) } } // best effort: stray temp file only

        let startDisplay = env.displayUnderPointer()
        let args = ScreencaptureArguments.make(
            mode: mode, options: options, displayNumber: startDisplay.number, outputPath: tempPath
        )
        log.debug("screencapture \(args.joined(separator: " "), privacy: .public)")

        let (status, stderr) = try await run(args)
        let capturedAt = env.now()

        let outcome = CaptureOutcome.classify(
            status: status, stderr: stderr, fileExists: fm.fileExists(atPath: tempPath), hasPermission: env.hasPermission
        )
        switch outcome {
        case .cancelled:
            log.info("Capture cancelled")
            return nil
        case .failure(let error):
            log.error("Capture failed (status \(status)): \(stderr, privacy: .public)")
            throw error
        case .image:
            break
        }

        guard let info = ImageInfo(url: temp) else {
            throw CaptureError.failed("Unreadable capture output")
        }
        let name = FileNaming.format(options.fileNamePattern, date: capturedAt)
        let final = try place(temp, in: options.destinationDirectory, base: name)

        // Only interactive modes need the (cheap, ≤64 px) corner check.
        let interactive = mode == .area || mode == .allInOne
        let corners = interactive && info.hasAlpha && ImageInfo.cornersAreTransparent(url: final)
        let kind = CaptureOutcome.kind(for: mode, transparentCorners: corners)
        let displayID = mode == .fullscreen ? startDisplay.displayID : env.displayUnderPointer().displayID
        log.info("Captured \(final.lastPathComponent, privacy: .public) \(Int(info.pixelSize.width))×\(Int(info.pixelSize.height)) @\(info.scale)x")
        return CaptureResult(
            fileURL: final,
            displayName: final.deletingPathExtension().lastPathComponent,
            kind: kind,
            pixelSize: info.pixelSize,
            scale: info.scale,
            displayID: displayID,
            createdAt: capturedAt
        )
    }

    /// Moves `temp` to the first free `base[ n].png` in `directory`. Retries if
    /// another writer took the name between the check and the move.
    private func place(_ temp: URL, in directory: URL, base: String) throws -> URL {
        let fm = FileManager.default
        var lastError: Error?
        for _ in 0..<5 {
            let final = FileNaming.uniqueURL(in: directory, base: base, ext: "png")
            do {
                try fm.moveItem(at: temp, to: final)
                return final
            } catch CocoaError.fileWriteFileExists {
                lastError = CocoaError(.fileWriteFileExists)
                continue
            } catch {
                lastError = error
                break
            }
        }
        throw CaptureError.failed("Cannot move capture into place: \(lastError?.localizedDescription ?? "unknown")")
    }

    /// Runs the tool and waits for it to exit. Returns exit status and stderr.
    private func run(_ args: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = env.executable
        process.arguments = args
        let errPipe = Pipe()
        process.standardError = errPipe
        process.standardOutput = FileHandle.nullDevice
        let status: Int32 = try await withCheckedThrowingContinuation { continuation in
            process.terminationHandler = { p in continuation.resume(returning: p.terminationStatus) }
            do {
                try process.run()
            } catch {
                process.terminationHandler = nil
                continuation.resume(throwing: CaptureError.failed("Cannot launch screencapture: \(error.localizedDescription)"))
            }
        }
        let data = errPipe.fileHandleForReading.readDataToEndOfFile()
        let stderr = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return (status, stderr)
    }
}
