import AnnotationKit
import Foundation
import ShotzCore

/// Closing a capture's editor hands the capture back to the stack (SPEC §4.6):
/// the document is saved (by the window), the annotated result is flattened to the
/// rendered URL at full resolution, and only then is the hand-back reported.
extension EditorCoordinator {
    func captureWindowClosed(_ capture: CaptureResult, _ info: EditorWindowController.CloseInfo) {
        guard !info.isTerminating else { return } // quitting: documents are saved, no cards (SPEC §4.6)
        let target = renderedURL?(capture.id)
        Task { @MainActor [weak self] in
            let rendered = await Self.writeRendered(info.document, base: info.base, to: target)
            self?.log.notice("Editor closed for \(capture.displayName, privacy: .public): rendered \(rendered?.lastPathComponent ?? "none", privacy: .public)")
            // Reopened while rendering: the editor owns the capture again, no card (SPEC §4.6).
            guard self?.isOpen(capture.id) == false else { return }
            self?.captureClosed?(capture, rendered, info.displayID)
        }
    }

    /// True when the document differs from the bare capture.
    nonisolated static func hasEdits(_ document: AnnotationDocument) -> Bool {
        !document.objects.isEmpty || document.crop != nil || document.background != nil
    }

    /// Writes the flattened PNG atomically off the main thread and returns its URL, or
    /// removes a stale one and returns nil when there are no edits (or no target).
    nonisolated static func writeRendered(_ document: AnnotationDocument, base: BaseImageProvider, to url: URL?) async -> URL? {
        guard let url else { return nil }
        let log = ShotzLog.logger("AnnotationEditor")
        return await Task.detached(priority: .userInitiated) { () -> URL? in
            let fm = FileManager.default
            guard hasEdits(document) else {
                if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                    do { try fm.removeItem(at: url) } catch {
                        log.error("Cannot remove stale rendered image: \(error.localizedDescription, privacy: .public)")
                    }
                }
                return nil
            }
            let dir = url.deletingLastPathComponent()
            let temp = dir.appending(path: ".\(UUID().uuidString).png", directoryHint: .notDirectory)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try DocumentExport.write(document, base: base, to: temp, format: .png, quality: 1, scale: 1)
                if fm.fileExists(atPath: url.path(percentEncoded: false)) {
                    _ = try fm.replaceItemAt(url, withItemAt: temp)
                } else {
                    try fm.moveItem(at: temp, to: url)
                }
                return url
            } catch {
                log.error("Cannot write rendered image: \(String(describing: error), privacy: .public)")
                try? fm.removeItem(at: temp) // leftover temp file, if any
                return nil
            }
        }.value
    }
}
