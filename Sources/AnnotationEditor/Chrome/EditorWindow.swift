import AppKit

/// Routes ⌘-key equivalents to the editor menu (there is no menu bar in an
/// agent app) and sends undo/redo to the document store rather than the
/// window's own undo manager.
@MainActor final class EditorWindow: NSWindow {
    var commandMenu: NSMenu?
    /// Receives undo:/redo: when no text view handles them first.
    weak var undoTarget: EditorUndoTarget?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) { return true }
        return commandMenu?.performKeyEquivalent(with: event) ?? false
    }

    /// Esc in an options-bar or panel control hands the keyboard back to the canvas.
    var onCancel: (() -> Void)?

    override func cancelOperation(_ sender: Any?) {
        if let onCancel { onCancel() } else { super.cancelOperation(sender) }
    }

    @objc func undo(_ sender: Any?) { undoTarget?.undoDocument() }
    @objc func redo(_ sender: Any?) { undoTarget?.redoDocument() }

    override func validateMenuItem(_ item: NSMenuItem) -> Bool {
        switch item.action {
        case #selector(EditorWindow.undo(_:)):
            item.title = undoTarget?.undoTitle ?? String(localized: "Undo")
            return undoTarget?.canUndoDocument ?? false
        case #selector(EditorWindow.redo(_:)):
            item.title = undoTarget?.redoTitle ?? String(localized: "Redo")
            return undoTarget?.canRedoDocument ?? false
        default:
            return super.validateMenuItem(item)
        }
    }
}

@MainActor protocol EditorUndoTarget: AnyObject {
    func undoDocument()
    func redoDocument()
    var canUndoDocument: Bool { get }
    var canRedoDocument: Bool { get }
    var undoTitle: String { get }
    var redoTitle: String { get }
}
