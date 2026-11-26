import AppKit

/// Drag-out handle in the toolbar: drags the flattened file into other apps.
/// The file is rendered when the drag starts.
@MainActor final class DragHandleView: NSView, NSDraggingSource {
    /// Produces the file to drag (rendered at full resolution).
    var makeFile: (() -> URL?)?
    private let imageView = NSImageView()
    private var mouseDownEvent: NSEvent?

    override init(frame: NSRect) {
        super.init(frame: frame)
        imageView.image = NSImage(systemSymbolName: "hand.draw", accessibilityDescription: nil)
        imageView.symbolConfiguration = .init(pointSize: 15, weight: .regular)
        imageView.contentTintColor = .secondaryLabelColor
        imageView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: centerYAnchor),
            widthAnchor.constraint(equalToConstant: 30),
            heightAnchor.constraint(equalToConstant: 24),
        ])
        toolTip = String(localized: "Drag the finished image into another app")
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(String(localized: "Drag image"))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .openHand) }

    override func mouseDown(with event: NSEvent) { mouseDownEvent = event }

    override func mouseDragged(with event: NSEvent) {
        guard let down = mouseDownEvent else { return }
        let d = hypot(event.locationInWindow.x - down.locationInWindow.x, event.locationInWindow.y - down.locationInWindow.y)
        guard d >= 3 else { return }
        mouseDownEvent = nil
        startDrag(with: down, from: self)
    }

    /// Starts a file drag (also used by the title-bar proxy icon).
    func startDrag(with event: NSEvent, from view: NSView) {
        guard let url = makeFile?() else { return }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        let preview = NSImage(contentsOf: url) ?? NSImage()
        let aspect = preview.size.height > 0 ? preview.size.width / preview.size.height : 1
        let w: CGFloat = 120, h = w / max(aspect, 0.1)
        let p = view.convert(event.locationInWindow, from: nil)
        item.setDraggingFrame(NSRect(x: p.x - w / 2, y: p.y - h / 2, width: w, height: h), contents: preview)
        view.beginDraggingSession(with: [item], event: event, source: self)
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : []
    }
}
