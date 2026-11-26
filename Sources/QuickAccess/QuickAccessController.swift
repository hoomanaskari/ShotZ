import os
import AppKit
import ShotzCore

/// The quick-access stack. TODO(engineer B): replace this placeholder with the
/// real per-display card stack (ARCHITECTURE §4, SPEC §4).
@MainActor public final class QuickAccessController: QuickAccessPresenting {
    public weak var delegate: QuickAccessDelegate?

    private let settings: SettingsStore
    private let exporter: ExportService
    private var panels: [CaptureResult.ID: PlaceholderCardPanel] = [:]
    private let log = ShotzLog.logger("QuickAccess")

    public init(settings: SettingsStore, exporter: ExportService) {
        self.settings = settings
        self.exporter = exporter
    }

    public func present(_ capture: CaptureResult) {
        log.info("Present \(capture.displayName, privacy: .public)")
        dismiss(id: capture.id)
        let panel = PlaceholderCardPanel(capture: capture, width: settings.quickAccessSize.width)
        panel.onAnnotate = { [weak self] in
            guard let self else { return }
            self.dismiss(id: capture.id)
            self.delegate?.quickAccess(requestAnnotate: capture)
        }
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.dismiss(id: capture.id)
            self.delegate?.quickAccess(didClose: capture, deleteFile: false)
        }
        panels[capture.id] = panel
        layout()
        panel.orderFrontRegardless()
    }

    public func dismiss(id: CaptureResult.ID) {
        panels.removeValue(forKey: id)?.close()
        layout()
    }

    public func dismissAll() {
        for panel in panels.values { panel.close() }
        panels.removeAll()
    }

    /// Placeholder layout: newest at the bottom-left of the main screen.
    private func layout() {
        guard let frame = NSScreen.main?.visibleFrame else { return }
        var y = frame.minY + 16
        let ordered = panels.values.sorted { $0.capture.createdAt > $1.capture.createdAt }
        for panel in ordered {
            panel.setFrameOrigin(NSPoint(x: frame.minX + 16, y: y))
            y += panel.frame.height + 10
        }
    }
}
