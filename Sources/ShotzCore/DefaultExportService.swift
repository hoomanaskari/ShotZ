import os
import AppKit
import Foundation

/// The one `ExportService` implementation, shared by the stack and the editor.
public struct DefaultExportService: ExportService {
    private let paths: ShotzPaths
    private let configuration: @Sendable () -> ExportConfiguration
    private let log = ShotzLog.logger("Export")

    /// - Parameter configuration: called per export to read current settings.
    public init(
        paths: ShotzPaths = .default,
        configuration: @escaping @Sendable () -> ExportConfiguration = { .current() }
    ) {
        self.paths = paths
        self.configuration = configuration
    }

    // MARK: Pasteboard

    /// Puts PNG + TIFF + a file URL (export-named temp copy) on the general pasteboard.
    public func copyToPasteboard(imageAt url: URL) async throws {
        let data = try Data(contentsOf: url)
        guard let rep = NSBitmapImageRep(data: data) else {
            throw ExportError.unreadableImage(url.lastPathComponent)
        }
        let png = url.pathExtension.lowercased() == "png" ? data : rep.representation(using: .png, properties: [:])
        let tiff = rep.tiffRepresentation
        let fileURL = try exportFileURLForDrag(imageAt: url, suggestedName: url.deletingPathExtension().lastPathComponent)

        try await MainActor.run {
            let item = NSPasteboardItem()
            if let png { item.setData(png, forType: .png) }
            if let tiff { item.setData(tiff, forType: .tiff) }
            item.setString(fileURL.absoluteString, forType: .fileURL)
            let pb = NSPasteboard.general
            pb.clearContents()
            guard pb.writeObjects([item]) else { throw ExportError.pasteboardWriteFailed }
        }
    }

    // MARK: Save

    public func saveToExportFolder(imageAt url: URL, suggestedName: String, askDestination: Bool) async throws -> URL? {
        let config = configuration()
        let destination: URL
        if askDestination {
            guard let chosen = await Self.runSavePanel(
                directory: config.exportFolder,
                name: FileNaming.candidate(base: FileNaming.sanitize(suggestedName), ext: config.format.fileExtension, attempt: 1)
            ) else { return nil }
            destination = chosen
            // The panel already confirmed replacement.
            if FileManager.default.fileExists(atPath: chosen.path(percentEncoded: false)) {
                try FileManager.default.removeItem(at: chosen)
            }
        } else {
            try FileManager.default.createDirectory(at: config.exportFolder, withIntermediateDirectories: true)
            destination = FileNaming.uniqueURL(in: config.exportFolder, base: suggestedName, ext: config.format.fileExtension)
        }
        try ImageTranscoder.write(source: url, to: destination, config: config)
        log.info("Saved export \(destination.lastPathComponent, privacy: .private)")
        return destination
    }

    @MainActor
    private static func runSavePanel(directory: URL, name: String) async -> URL? {
        let panel = NSSavePanel()
        panel.directoryURL = directory
        panel.nameFieldStringValue = name
        panel.canCreateDirectories = true
        NSApp.activate()
        return await withCheckedContinuation { continuation in
            panel.begin { response in
                continuation.resume(returning: response == .OK ? panel.url : nil)
            }
        }
    }

    // MARK: Drag

    /// Writes an export-named, export-formatted copy into a fresh temp folder
    /// (so the dropped file carries the exact name, no counter).
    public func exportFileURLForDrag(imageAt url: URL, suggestedName: String) throws -> URL {
        let config = configuration()
        let dir = paths.dragExports.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let destination = FileNaming.uniqueURL(in: dir, base: suggestedName, ext: config.format.fileExtension)
        try ImageTranscoder.write(source: url, to: destination, config: config)
        return destination
    }
}
