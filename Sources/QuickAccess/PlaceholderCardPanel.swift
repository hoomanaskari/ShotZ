import AppKit
import ShotzCore

/// Minimal non-activating card: thumbnail, double-click = annotate, Close button.
/// TODO(engineer B): delete when the real stack lands.
@MainActor final class PlaceholderCardPanel: NSPanel {
    let capture: CaptureResult
    var onAnnotate: (() -> Void)?
    var onClose: (() -> Void)?

    init(capture: CaptureResult, width: CGFloat) {
        self.capture = capture
        let size = NSSize(width: width, height: width * 10 / 16)
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        sharingType = .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true

        let content = NSView(frame: NSRect(origin: .zero, size: size))
        content.wantsLayer = true
        content.layer?.cornerRadius = 10
        content.layer?.masksToBounds = true
        content.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor

        let imageView = ClickableImageView(frame: content.bounds)
        imageView.image = NSImage(contentsOf: capture.fileURL)
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.autoresizingMask = [.width, .height]
        imageView.onDoubleClick = { [weak self] in self?.onAnnotate?() }
        content.addSubview(imageView)

        let close = NSButton(title: "×", target: nil, action: nil)
        close.bezelStyle = .circular
        close.frame = NSRect(x: 4, y: size.height - 28, width: 24, height: 24)
        close.setAccessibilityLabel(String(localized: "Close"))
        close.target = self
        close.action = #selector(closeTapped)
        content.addSubview(close)

        contentView = content
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    @objc private func closeTapped() { onClose?() }
}

@MainActor final class ClickableImageView: NSImageView {
    var onDoubleClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { onDoubleClick?() } else { super.mouseDown(with: event) }
    }
}
