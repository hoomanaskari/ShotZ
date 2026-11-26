import AnnotationKit
import CoreGraphics
import Foundation

/// T: click to place and type, drag to set a wrap width. A plain click on an
/// existing object selects it (SPEC 5.2); a double-click on a text edits it.
/// Editing itself happens in the canvas (`TextEditingHost`); the commit/cancel
/// rules live in `EditorModel.commitText`.
@MainActor final class TextTool: Tool, ModelBound {
    let kind = ToolKind.text
    weak var model: EditorModel? { didSet { manipulator = SelectionManipulator(model: model) } }
    private var manipulator = SelectionManipulator(model: nil)
    private var start: CGPoint?
    private var current: CGPoint?
    private var clickedObject: AnnotationObject.ID?
    /// A click that ended a running edit does not place a new text.
    private var endedEdit = false

    func mouseDown(_ event: ToolEvent) {
        guard let model else { return }
        endedEdit = false
        if model.textHost?.isEditingText == true {
            model.textHost?.endEditing()
            endedEdit = true
            return
        }
        if event.clickCount >= 2, let hit = model.hitObject(at: event.point), model.beginEditing(hit) { return }
        if manipulator.begin(event) { return }
        clickedObject = model.hitObject(at: event.point)
        start = event.point
        current = event.point
    }

    func mouseDragged(_ event: ToolEvent) {
        if manipulator.isActive { manipulator.drag(event); return }
        current = event.point
        if let start, let model {
            let r = CGRect(x: min(start.x, event.point.x), y: min(start.y, event.point.y),
                           width: abs(event.point.x - start.x), height: abs(event.point.y - start.y))
            model.marquee = r.width >= model.dragThreshold ? r : nil
        }
    }

    func mouseUp(_ event: ToolEvent) {
        if manipulator.isActive { manipulator.end(event); return }
        defer { start = nil; current = nil; clickedObject = nil; model?.marquee = nil }
        guard let model, let start, !endedEdit else { return }
        let end = current ?? start
        let dragged = hypot(end.x - start.x, end.y - start.y) >= model.dragThreshold
        if !dragged, let hit = clickedObject {
            model.select([hit])
            return
        }
        let width = abs(end.x - start.x)
        let origin = dragged ? CGPoint(x: min(start.x, end.x), y: min(start.y, end.y)) : start
        let object = model.newTextObject(at: origin, wrapWidth: width >= model.dragThreshold * 4 ? width : nil)
        model.clearSelection()
        model.textHost?.beginEditing(object, isNew: true)
    }

    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor {
        manipulator.cursor(at: point) ?? .iBeam
    }

    func deactivate() {
        manipulator.cancel()
        model?.marquee = nil
    }
}

extension EditorModel {
    /// A new, empty text object in the Text tool's style (not yet in the document).
    func newTextObject(at origin: CGPoint, wrapWidth: CGFloat?) -> AnnotationObject {
        let s = settings(for: .text)
        let style = style(for: .text)
        // The click marks where the first glyph starts; the box begins one inset earlier.
        let inset = wrapWidth == nil ? TextLayout.insets(fontSize: style.fontSize) : .zero
        let boxOrigin = CGPoint(x: origin.x - inset.width, y: origin.y - inset.height)
        return AnnotationObject(
            shape: .text(TextBox(origin: boxOrigin, wrapWidth: wrapWidth, string: "", style: s.textStyle)),
            style: style
        )
    }

    /// Ends an in-place edit. Empty text is discarded; a new text is added in
    /// one undo step; an edit of an existing text is one step.
    func commitText(_ object: AnnotationObject, string: String, isNew: Bool) {
        hiddenObjectIDs.remove(object.id)
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard case .text(var box) = object.shape else { return }
        box.string = string
        var updated = object
        updated.shape = .text(box)
        if trimmed.isEmpty {
            if !isNew {
                store.perform(String(localized: "Delete Text")) { doc in doc[id: object.id] = nil }
            }
            clearSelection()
            return
        }
        if isNew {
            store.perform(String(localized: "Add Text")) { doc in doc.objects.append(updated) }
            select([updated.id])
            didFinishDrawing()
        } else {
            store.perform(String(localized: "Edit Text")) { doc in doc[id: object.id] = updated }
            select([updated.id])
        }
    }
}
