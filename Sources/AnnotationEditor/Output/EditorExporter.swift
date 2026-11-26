import os
import AnnotationKit
import AppKit
import ShotzCore
import UniformTypeIdentifiers

/// Output for one editor window (SPEC §5.5). Every path renders through
/// `DocumentExport` at full base-image resolution, never from the screen.
@MainActor final class EditorExporter {
    private let exporter: ExportService
    private let settings: SettingsStore
    private let log = ShotzLog.logger("AnnotationEditor")
    /// The previous Save of this document; Save overwrites it.
    private(set) var lastExportURL: URL?

    init(exporter: ExportService, settings: SettingsStore) {
        self.exporter = exporter
        self.settings = settings
    }

    enum Failure: LocalizedError {
        case render(String)
        var errorDescription: String? {
            switch self {
            case .render(let reason): String(localized: "The image could not be rendered (\(reason)).")
            }
        }
    }

    /// Renders a lossless PNG of the flattened document into a fresh temp folder.
    func renderTemporaryPNG(_ document: AnnotationDocument, name: String, scale: CGFloat = 1) throws -> URL {
        let dir = ShotzPaths.default.temporary.appending(path: "Editor/\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appending(path: FileNaming.sanitize(name) + ".png", directoryHint: .notDirectory)
        let start = ContinuousClock.now
        do {
            try DocumentExport.write(document, to: url, format: .png, quality: 1, scale: scale)
        } catch {
            throw Failure.render(String(describing: error))
        }
        log.info("Rendered \(Int(document.imageRect.width))x\(Int(document.imageRect.height)) in \(ContinuousClock.now - start, privacy: .public)")
        return url
    }

    func copy(_ document: AnnotationDocument, name: String) async throws {
        let url = try renderTemporaryPNG(document, name: name)
        try await exporter.copyToPasteboard(imageAt: url)
    }

    /// Writes to the export folder without asking (or asks, per setting), or
    /// overwrites the previous export of this document. Returns the file.
    func save(_ document: AnnotationDocument, name: String) async throws -> URL? {
        if let previous = lastExportURL, FileManager.default.fileExists(atPath: previous.path(percentEncoded: false)) {
            let format = ImageFormat.allCases.first { $0.fileExtension == previous.pathExtension.lowercased() } ?? settings.exportFormat
            let scale: CGFloat = settings.retinaScale == .downscaleTo1x ? 1 / max(document.scale, 1) : 1
            try DocumentExport.write(document, to: previous, format: format, quality: 0.9, scale: scale)
            return previous
        }
        let url = try renderTemporaryPNG(document, name: name)
        let saved = try await exporter.saveToExportFolder(imageAt: url, suggestedName: name, askDestination: settings.askDestinationWhenSaving)
        if let saved { lastExportURL = saved }
        return saved
    }

    /// Save As…: format, quality and 1×/2× scale.
    func saveAs(_ document: AnnotationDocument, name: String, window: NSWindow) async throws -> URL? {
        let panel = NSSavePanel()
        let accessory = SaveAsAccessory(format: settings.exportFormat, panel: panel)
        panel.accessoryView = accessory.view
        panel.directoryURL = settings.exportFolder
        panel.nameFieldStringValue = FileNaming.sanitize(name) + "." + settings.exportFormat.fileExtension
        panel.allowedContentTypes = [settings.exportFormat.utType]
        panel.canCreateDirectories = true
        let response = await panel.beginSheetModal(for: window)
        guard response == .OK, let url = panel.url else { return nil }
        // 1× = one pixel per point; 2× = two (the native size of Retina captures).
        let outputScale = CGFloat(accessory.scaleFactor) / max(document.scale, 0.0001)
        try DocumentExport.write(document, to: url, format: accessory.format, quality: accessory.quality, scale: outputScale)
        return url
    }

    /// A file for drag-out with the export name and format.
    func dragFile(_ document: AnnotationDocument, name: String) throws -> URL {
        let url = try renderTemporaryPNG(document, name: name)
        return try exporter.exportFileURLForDrag(imageAt: url, suggestedName: name)
    }

    func print(_ document: AnnotationDocument, name: String, window: NSWindow) throws {
        let url = try renderTemporaryPNG(document, name: name)
        guard let image = NSImage(contentsOf: url) else { throw Failure.render("unreadable") }
        let pointSize = NSSize(width: document.imageRect.width / max(document.scale, 1),
                               height: document.imageRect.height / max(document.scale, 1))
        image.size = pointSize
        let view = NSImageView(frame: NSRect(origin: .zero, size: pointSize))
        view.image = image
        view.imageScaling = .scaleProportionallyUpOrDown
        let info = NSPrintInfo.shared.copy() as? NSPrintInfo ?? NSPrintInfo()
        info.horizontalPagination = .fit
        info.verticalPagination = .fit
        info.isHorizontallyCentered = true
        info.isVerticallyCentered = true
        info.orientation = pointSize.width > pointSize.height ? .landscape : .portrait
        let op = NSPrintOperation(view: view, printInfo: info)
        op.jobTitle = name
        op.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
    }
}
