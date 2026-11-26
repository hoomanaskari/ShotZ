import AnnotationKit
import AppKit

/// Placeholder editor window: shows the base image. TODO(engineer D).
@MainActor final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let store: DocumentStore
    var onClose: (() -> Void)?

    init(store: DocumentStore, title: String) {
        self.store = store
        let doc = store.document
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let pointSize = NSSize(width: doc.pixelSize.width / max(doc.scale, 1), height: doc.pixelSize.height / max(doc.scale, 1))
        let fit = min(1, screen.width * 0.8 / max(pointSize.width, 1), screen.height * 0.8 / max(pointSize.height, 1))
        let size = NSSize(width: max(720, pointSize.width * fit), height: max(480, pointSize.height * fit))

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        let imageView = NSImageView(frame: NSRect(origin: .zero, size: size))
        imageView.image = NSImage(contentsOf: doc.baseImageURL)
        imageView.imageScaling = .scaleProportionallyDown
        imageView.autoresizingMask = [.width, .height]
        window.contentView = imageView
        window.center()
        super.init(window: window)
        window.delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func windowWillClose(_ notification: Notification) {
        onClose?()
    }
}
