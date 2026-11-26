import os
import CoreGraphics
import Foundation
import ShotzCore

/// Phase 1 engine: drives `/usr/sbin/screencapture` (ARCHITECTURE §3).
public actor SystemCaptureEngine: CaptureEngine {
    private let executable = URL(filePath: "/usr/sbin/screencapture")
    private var isCapturing = false
    private let log = ShotzLog.logger("CaptureKit")

    public init() {}

    public func capture(_ mode: CaptureMode, options: CaptureOptions) async throws -> CaptureResult? {
        guard !isCapturing else { throw CaptureError.busy }
        isCapturing = true
        defer { isCapturing = false }

        let fm = FileManager.default
        do {
            try fm.createDirectory(at: options.destinationDirectory, withIntermediateDirectories: true)
        } catch {
            throw CaptureError.failed("Cannot create captures folder: \(error.localizedDescription)")
        }
        let startedAt = Date()
        let temp = options.destinationDirectory.appending(path: ".capture-\(UUID().uuidString).png", directoryHint: .notDirectory)
        let display = DisplayLocator.displayUnderPointer()
        let args = ScreencaptureArguments.make(
            mode: mode, options: options, displayNumber: display.number, outputPath: temp.path(percentEncoded: false)
        )
        log.debug("screencapture \(args.joined(separator: " "), privacy: .public)")

        let (status, stderr) = try await run(args)
        let tempPath = temp.path(percentEncoded: false)
        guard fm.fileExists(atPath: tempPath) else {
            if status == 0 || stderr.isEmpty {
                log.info("Capture cancelled")
                return nil
            }
            if !CGPreflightScreenCaptureAccess() { throw CaptureError.permissionDenied }
            throw CaptureError.failed(stderr)
        }

        guard let info = ImageInfo(url: temp) else {
            try? fm.removeItem(at: temp) // best effort cleanup of an unreadable temp file
            throw CaptureError.failed("Unreadable capture output")
        }
        let name = FileNaming.format(options.fileNamePattern, date: startedAt)
        let final = FileNaming.uniqueURL(in: options.destinationDirectory, base: name, ext: "png")
        do {
            try fm.moveItem(at: temp, to: final)
        } catch {
            throw CaptureError.failed("Cannot move capture into place: \(error.localizedDescription)")
        }
        let kind: CaptureKind = switch mode {
        case .fullscreen: .fullscreen
        case .window: .window
        // TODO(engineer B): detect window captures made via Space in area/all-in-one mode.
        case .area, .allInOne: .area
        }
        let displayID = mode == .fullscreen ? display.displayID : DisplayLocator.displayUnderPointer().displayID
        return CaptureResult(
            fileURL: final,
            displayName: final.deletingPathExtension().lastPathComponent,
            kind: kind,
            pixelSize: info.pixelSize,
            scale: info.scale,
            displayID: displayID,
            createdAt: startedAt
        )
    }

    /// Runs screencapture and waits for it to exit. Returns exit status and stderr.
    private func run(_ args: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = executable
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
