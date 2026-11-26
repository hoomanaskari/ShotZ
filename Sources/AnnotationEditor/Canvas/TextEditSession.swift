import AnnotationKit
import AppKit

/// In-place text editing on the canvas (SPEC §5.3 Text): an `NSTextView` in
/// the magnified document view, so it scales with the zoom. Return = new line;
/// ⌘Return, Esc or a click elsewhere commits; empty text is discarded.
///
/// What you see while typing is AnnotationKit's own rendering of the draft (with its
/// pill or outline), in a layer under the text view; the text view itself draws only
/// the caret and selection (its glyphs are clear), so the look never changes on commit.
@MainActor final class TextEditSession: NSObject, TextEditingHost, NSTextViewDelegate {
    private weak var canvas: CanvasView?
    private var textView: CommitTextView?
    private var object: AnnotationObject?
    private var isNew = false
    /// The draft as the renderer draws it, and a thin frame around the text object.
    let previewLayer = CALayer()
    private let frameLayer = CALayer()

    init(canvas: CanvasView) {
        self.canvas = canvas
    }

    var isEditingText: Bool { textView != nil }

    /// The renderer's font: the system UI font (emphasized when bold).
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
        // Glyphs come from the preview layer; the caret takes the rendered text colour.
        tv.textColor = .clear
        let glyphColor = box.style.decoration == .solidPill || box.style.decoration == .translucentPill
            ? object.style.color.contrastingTextColor : object.style.color.withAlpha(1)
        tv.insertionPointColor = NSColor(cgColor: glyphColor.cgColor) ?? .systemRed
        tv.alignment = switch box.style.alignment {
        case .left: .left
        case .center: .center
        case .right: .right
        }
        if box.style.decoration == .outlined {
            // Outlined text is laid out with open tracking (AnnotationKit's TextLayout); match it
            // so the caret and the committed text line up. Mirrors max(fontSize × 0.075, 1) × 1.1.
            tv.typingAttributes[.kern] = max(object.style.fontSize * 0.075, 1) * 1.1
        }
        tv.string = box.string
        if let kern = tv.typingAttributes[.kern] {
            tv.textStorage?.addAttribute(.kern, value: kern, range: NSRange(location: 0, length: (tv.string as NSString).length))
        }
        tv.isVerticallyResizable = true
        // Glyphs sit where AnnotationKit lays them out (TextLayout.textRect).
        let layout = TextLayout(box: box, fontSize: object.style.fontSize)
        if box.wrapWidth != nil {
            tv.isHorizontallyResizable = false
            tv.textContainer?.widthTracksTextView = true
            tv.frame = NSRect(x: 0, y: 0, width: layout.textRect.width, height: object.style.fontSize * 1.3)
        } else {
            tv.isHorizontallyResizable = true
            tv.textContainer?.widthTracksTextView = false
            tv.textContainer?.containerSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
            tv.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)
        }
        tv.minSize = NSSize(width: object.style.fontSize * 0.6, height: object.style.fontSize * 1.2)
        for l in [previewLayer, frameLayer] {
            l.actions = ObjectLayerStore.noActions.merging(["borderWidth": NSNull()]) { a, _ in a }
            l.anchorPoint = .zero
            canvas.layers.world.addSublayer(l)
        }
        frameLayer.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.8).cgColor
        frameLayer.borderWidth = 1 / max(canvas.model.pointsPerPixel, 0.01)
        let origin = canvas.canvasLayout.toCanvas(layout.textRect.origin)
        tv.setFrameOrigin(origin)
        canvas.addSubview(tv)
        textView = tv
        resize()
        updatePreview()
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
        previewLayer.removeFromSuperlayer()
        previewLayer.contents = nil
        frameLayer.removeFromSuperlayer()
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

    func textDidChange(_ notification: Notification) {
        resize()
        updatePreview()
    }

    /// The draft with the typed string, as it will be committed.
    private var draft: AnnotationObject? {
        guard let tv = textView, var object, case .text(var box) = object.shape else { return nil }
        box.string = tv.string
        object.shape = .text(box)
        return object
    }

    /// Re-renders the draft through AnnotationRenderer (pill, outline, colour, opacity).
    private func updatePreview() {
        guard let canvas, let draft, case .text(let box) = draft.shape else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        frameLayer.frame = TextLayout(box: box, fontSize: draft.style.fontSize).frame
        if !box.string.isEmpty, let bitmap = canvas.layers.bitmap(for: draft, document: canvas.model.document) {
            previewLayer.contents = bitmap.image
            previewLayer.frame = bitmap.frame
        } else {
            previewLayer.contents = nil
        }
    }

    func textView(_ textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            endEditing()
            return true
        }
        return false
    }

    /// Updates the zoom-dependent border width.
    func zoomChanged(pointsPerPixel: CGFloat) {
        guard textView != nil else { return }
        frameLayer.borderWidth = 1 / max(pointsPerPixel, 0.01)
        updatePreview() // crisp at the new zoom
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
