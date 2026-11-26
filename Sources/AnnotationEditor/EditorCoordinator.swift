import os
import AnnotationKit
import AppKit
import ShotzCore

/// Opens one editor window per capture. TODO(engineer D): real editor (ARCHITECTURE §6).
@MainActor public final class EditorCoordinator: AnnotationEditing {
    private let settings: SettingsStore
    private let exporter: ExportService
    /// Where each capture's editable document lives (`HistoryStore.documentURL(for:)`).
    private let documentURL: (CaptureResult.ID) -> URL
    private var windows: [EditorWindowController] = []
    private let log = ShotzLog.logger("AnnotationEditor")

    public init(
        settings: SettingsStore,
        exporter: ExportService,
        documentURL: @escaping (CaptureResult.ID) -> URL
    ) {
        self.settings = settings
        self.exporter = exporter
        self.documentURL = documentURL
    }

    public func openEditor(for capture: CaptureResult) {
        let url = documentURL(capture.id)
        let document = (try? AnnotationDocument.load(from: url)) // no saved document yet is normal
            ?? AnnotationDocument(baseImageURL: capture.fileURL, pixelSize: capture.pixelSize, scale: capture.scale)
        open(DocumentStore(document: document), title: capture.displayName)
    }

    public func openEditor(imageAt url: URL) {
        guard let image = NSImage(contentsOf: url),
              let rep = image.representations.first
        else {
            log.error("Cannot open image \(url.lastPathComponent, privacy: .public)")
            return
        }
        let pixelSize = CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        let scale = image.size.width > 0 ? pixelSize.width / image.size.width : 1
        let document = AnnotationDocument(baseImageURL: url, pixelSize: pixelSize, scale: scale)
        open(DocumentStore(document: document), title: url.deletingPathExtension().lastPathComponent)
    }

    private func open(_ store: DocumentStore, title: String) {
        let controller = EditorWindowController(store: store, title: title)
        controller.onClose = { [weak self, weak controller] in
            self?.windows.removeAll { $0 === controller }
        }
        windows.append(controller)
        NSApp.activate()
        controller.showWindow(nil)
    }
}
