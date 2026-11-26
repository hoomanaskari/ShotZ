import os
import AnnotationKit
import AppKit
import ImageIO
import ShotzCore

/// Opens one editor window per capture, reusing an open window (SPEC §5.1).
/// Loads the persisted editable document if there is one; the windows write
/// it back silently on change and on close.
@MainActor public final class EditorCoordinator: AnnotationEditing {
    private enum Key: Hashable {
        case capture(CaptureResult.ID)
        case file(URL)
    }

    private let settings: SettingsStore
    private let exporter: ExportService
    /// Where each capture's editable document lives (`HistoryStore.documentURL(for:)`).
    private let documentURL: (CaptureResult.ID) -> URL
    private var windows: [Key: EditorWindowController] = [:]
    private let library: ToolSettingsLibrary
    private let backgroundPresets: BackgroundPresets
    private let log = ShotzLog.logger("AnnotationEditor")

    public init(
        settings: SettingsStore,
        exporter: ExportService,
        documentURL: @escaping (CaptureResult.ID) -> URL
    ) {
        self.settings = settings
        self.exporter = exporter
        self.documentURL = documentURL
        library = ToolSettingsLibrary(defaults: settings.defaults)
        backgroundPresets = BackgroundPresets(defaults: settings.defaults)
    }

    public func openEditor(for capture: CaptureResult) {
        openEditor(for: capture, documentURL: documentURL(capture.id))
    }

    /// The stack's hand-off path, with the document location given explicitly
    /// (the development harness uses a scratch location instead of history's).
    @discardableResult
    func openEditor(for capture: CaptureResult, documentURL url: URL) -> EditorWindowController? {
        let key = Key.capture(capture.id)
        if bringToFront(key) { return windows[key] }
        var document = AnnotationDocument(baseImageURL: capture.fileURL, pixelSize: capture.pixelSize, scale: capture.scale)
        if FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) {
            do {
                var saved = try AnnotationDocument.load(from: url)
                // The capture file is the source of truth for the base image.
                saved.baseImageURL = capture.fileURL
                document = saved
            } catch {
                log.error("Ignoring unreadable editor document for \(capture.displayName, privacy: .public): \(error.localizedDescription, privacy: .public)")
            }
        }
        return open(document, title: capture.displayName, key: key, documentURL: url)
    }

    public func openEditor(imageAt url: URL) {
        let key = Key.file(url.standardizedFileURL)
        if bringToFront(key) { return }
        guard let info = Self.imageInfo(url) else {
            log.error("Cannot open image \(url.lastPathComponent, privacy: .public)")
            NSSound.beep()
            return
        }
        var document = AnnotationDocument(baseImageURL: url, pixelSize: info.pixelSize, scale: info.scale)
        // Development only: persist a file-opened image's document to test reopening.
        let debugDocument = ProcessInfo.processInfo.environment["SHOTZ_EDITOR_DOCUMENT"].map { URL(filePath: $0) }
        if let debugDocument, let saved = try? AnnotationDocument.load(from: debugDocument) { // absent on first run
            document = saved
        }
        _ = open(document, title: url.deletingPathExtension().lastPathComponent, key: key, documentURL: debugDocument)
    }

    /// ⌘N: the image on the clipboard, in a new editor.
    func openFromClipboard() {
        guard let image = NSImage(pasteboard: .general),
              let tiff = image.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
              let png = rep.representation(using: .png, properties: [:])
        else {
            NSSound.beep()
            return
        }
        let dir = ShotzPaths.default.temporary.appending(path: "Clipboard", directoryHint: .isDirectory)
        let name = FileNaming.sanitize(String(localized: "Clipboard Image"))
        let url = dir.appending(path: "\(name) \(UUID().uuidString.prefix(8)).png", directoryHint: .notDirectory)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try png.write(to: url, options: .atomic)
            openEditor(imageAt: url)
        } catch {
            log.error("Cannot keep clipboard image: \(error.localizedDescription, privacy: .public)")
            NSSound.beep()
        }
    }

    private func bringToFront(_ key: Key) -> Bool {
        guard let existing = windows[key] else { return false }
        NSApp.activate()
        existing.showWindow(nil)
        existing.window?.makeKeyAndOrderFront(nil)
        return true
    }

    @discardableResult
    private func open(_ document: AnnotationDocument, title: String, key: Key, documentURL: URL?) -> EditorWindowController? {
        let start = ContinuousClock.now
        let base = BaseImageProvider(url: document.baseImageURL)
        let image: CGImage
        do { image = try base.image() } catch {
            log.error("Cannot decode \(document.baseImageURL.lastPathComponent, privacy: .public): \(String(describing: error), privacy: .public)")
            NSSound.beep()
            return nil
        }
        let env = EditorEnvironment(
            settings: settings, exporter: exporter, library: library, backgroundPresets: backgroundPresets,
            openImage: { [weak self] url in self?.openEditor(imageAt: url) },
            openClipboard: { [weak self] in self?.openFromClipboard() }
        )
        let controller = EditorWindowController(
            store: DocumentStore(document: document), image: image, base: base, title: title, documentURL: documentURL, env: env
        )
        controller.onClose = { [weak self] in self?.windows[key] = nil }
        windows[key] = controller
        if EditorScriptRunner.isScripted {
            // Scripted development runs never take focus from the person using the Mac.
            controller.window?.orderBack(nil)
        } else {
            NSApp.activate()
            controller.showWindow(nil)
            controller.window?.makeKeyAndOrderFront(nil)
        }
        controller.zoomFit()
        EditorScriptRunner.startIfRequested(for: controller, coordinator: self)
        log.notice("Opened editor for \(title, privacy: .public) in \(ContinuousClock.now - start, privacy: .public)")
        return controller
    }

    /// Pixel size and scale (from DPI) without decoding the image.
    static func imageInfo(_ url: URL) -> (pixelSize: CGSize, scale: CGFloat)? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let dpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
        return (CGSize(width: w, height: h), max(1, (dpi / 72).rounded()))
    }

    var openWindowCount: Int { windows.count }
}
