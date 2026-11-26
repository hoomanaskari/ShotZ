import AppKit
import os
import Quartz

/// Shows one capture in the system Quick Look panel.
@MainActor final class QuickLookPresenter: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    /// Read by Quick Look's (nonisolated) data-source callbacks.
    private let current = OSAllocatedUnfairLock<URL?>(initialState: nil)

    var url: URL? { current.withLock { $0 } }

    var isShowing: Bool {
        QLPreviewPanel.sharedPreviewPanelExists() && (QLPreviewPanel.shared()?.isVisible ?? false)
    }

    /// Opens the preview for `url`, or closes it if it already shows `url`.
    func toggle(_ url: URL) {
        guard let panel = QLPreviewPanel.shared() else { return }
        if isShowing, self.url == url {
            panel.orderOut(nil)
            return
        }
        current.withLock { $0 = url }
        if panel.dataSource !== self {
            panel.dataSource = self
            panel.delegate = self
        }
        panel.reloadData()
        panel.currentPreviewItemIndex = 0
        panel.makeKeyAndOrderFront(nil)
    }

    /// Closes the preview if it shows `url` (its card went away).
    func closeIfShowing(_ url: URL) {
        guard isShowing, self.url == url else { return }
        QLPreviewPanel.shared()?.orderOut(nil)
    }

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        current.withLock { $0 == nil ? 0 : 1 }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        current.withLock { $0 }.map { $0 as NSURL }
    }
}
