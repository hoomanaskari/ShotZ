import AnnotationKit
import AppKit

/// In-place text editing on the canvas (SPEC §5.3 Text): an `NSTextView` in
/// the magnified document view, so it scales with the zoom. Return = new line;
/// ⌘Return, Esc or a click elsewhere commits; empty text is discarded.
@MainActor final class TextEditSession: NSObject, TextEditingHost, NSTextViewDelegate {
    private weak var canvas: CanvasView?
    private var textView: CommitTextView?
    private var object: AnnotationObject?
    private var isNew = false

    init(canvas: CanvasView) {
        self.canvas = canvas
    }

    var isEditingText: Bool { textView != nil }

    /// Shared with the renderer's expectations: system font, no padding.
    static func font(for object: AnnotationObject, box: TextBox) -> NSFont {
        NSFont.systemFont(ofSize: object.style.fontSize, weight: box.style.isBold ? .bold : .regular)
    }

    func beginEditing(_ object: AnnotationObject, isNew: Bool) {
        guard let canvas, case .text(let box) = object.shape else { return }
        if isEditingText { endEditing() }
        self.object = object
        self.isNew = isNew
        canvas.model.hiddenObjectIDs.insert(object.id)

        let tv = CommitTextView(frame: .zero)
        tv.session = self
        tv.delegate = self
        tv.isRichText = false
        tv.allowsUndo = true
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.textContainer?.lineFragmentPadding = 0
        tv.font = Self.font(for: object, box: box)
        let color = object.style.color.withAlpha(object.style.color.alpha * object.style.opacity)
        tv.textColor = NSColor(cgColor: color.cgColor) ?? .systemRed
        tv.insertionPointColor = tv.textColor ?? .systemRed
        tv.alignment = switch box.style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        tv.string = box.string
        tv.isVerticallyResizable = true
        if let wrap = box.wrapWidth {
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.frame = NSRect(x: 0, y: 0, width: wrap, height: object.style.fontSize * 1.3)
        } else {
            tv.isHorizontallyResizable = true
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        tv.minSize = NSSize(width: object.style.fontSize * 0.6, height: object.style.fontSize * 1.2)
        tv.wantsLayer = true
        tv.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        tv.layer?.borderWidth = 1 / max(canvas.model.pointsPerPixel, 0.01)
        let origin = canvas.canvasLayout.toCanvas(box.origin)
        tv.setFrameOrigin(origin)
        canvas.addSubview(tv)
        textView = tv
        resize()
        canvas.window?.makeFirstResponder(tv)
        tv.selectAll(nil)
        canvas.model.notify(.tool)
    }

    func endEditing() {
        guard let tv = textView, let object, let canvas else { return }
        textView = nil
        self.object = nil
        let string = tv.string
        tv.removeFromSuperview()
        canvas.window?.makeFirstResponder(canvas)
        canvas.model.commitText(object, string: string, isNew: isNew)
        canvas.model.notify(.tool)
    }

    /// Keeps the frame hugging the text.
    private func resize() {
        guard let tv = textView, let lm = tv.layoutManager, let container = tv.textContainer else { return }
        lm.ensureLayout(for: container)
        let used = lm.usedRect(for: container)
        let minH = tv.font.map { $0.ascender - $0.descender + $0.leading } ?? 20
        var size = tv.frame.size
        size.height = max(used.height, minH)
        if tv.isHorizontallyResizable { size.width = max(used.width + 2, tv.minSize.width) }
        tv.setFrameSize(size)
    }

    func textDidChange(_ notification: Notification) { resize() }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            return true
        }
        return false
    }

    /// Updates the zoom-dependent border width.
    func zoomChanged(pointsPerPixel: CGFloat) {
        textView?.layer?.borderWidth = 1 / max(pointsPerPixel, 0.01)
    }
}

/// ⌘Return commits.
final class CommitTextView: NSTextView {
    weak var session: TextEditSession?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 36 || event.keyCode == 76, event.modifierFlags.contains(.command) {
            session?.endEditing()
            return
        }
        super.keyDown(with: event)
    }
}
