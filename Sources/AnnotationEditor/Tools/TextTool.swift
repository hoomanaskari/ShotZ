import AnnotationKit
import CoreGraphics
import Foundation

/// T: click to place and type, drag to set a wrap width; click an existing
/// text to edit it. Editing itself happens in the canvas (`TextEditingHost`);
/// the commit/cancel rules live in `EditorModel.commitText`.
@MainActor final class TextTool: Tool, ModelBound {
    let kind = ToolKind.text
    weak var model: EditorModel? { didSet { manipulator = SelectionManipulator(model: model) } }
    private var manipulator = SelectionManipulator(model: nil)
    private var start: CGPoint?
    private var current: CGPoint?
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
        if manipulator.begin(event) { return }
        if let hit = model.hitObject(at: event.point), let object = model.document[id: hit], case .text = object.shape {
            model.select([hit])
            model.textHost?.beginEditing(object, isNew: false)
            return
        }
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
        defer { start = nil; current = nil; model?.marquee = nil }
        guard let model, let start, !endedEdit else { return }
        let end = current ?? start
        let width = abs(end.x - start.x)
        let origin = CGPoint(x: min(start.x, end.x), y: min(start.y, end.y))
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
        return AnnotationObject(
            shape: .text(TextBox(origin: origin, wrapWidth: wrapWidth, string: "", style: s.textStyle)),
            style: style(for: .text)
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
