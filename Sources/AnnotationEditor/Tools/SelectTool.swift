import AnnotationKit
import CoreGraphics

/// V: click, ⇧-click, marquee, handles, move/resize, ⌥-drag duplicate.
@MainActor final class SelectTool: Tool, ModelBound {
    let kind = ToolKind.select
    weak var model: EditorModel? { didSet { manipulator = SelectionManipulator(model: model) } }
    private var manipulator = SelectionManipulator(model: nil)
    private var marqueeStart: CGPoint?
    private var marqueeBase: [AnnotationObject.ID] = []

    func mouseDown(_ event: ToolEvent) {
        guard let model else { return }
        if event.clickCount >= 2, let hit = model.hitObject(at: event.point),
           let object = model.document[id: hit], case .text = object.shape {
            model.select([hit])
            model.textHost?.beginEditing(object, isNew: false)
            return
        }
        if manipulator.begin(event, allowMove: !event.modifiers.contains(.shift)) { return }
        if let hit = model.hitObject(at: event.point) {
            if event.modifiers.contains(.shift) {
                model.toggleSelection(hit)
            } else {
                model.select([hit])
                manipulator.beginMove(event)
            }
            return
        }
        marqueeStart = event.point
        marqueeBase = event.modifiers.contains(.shift) ? model.selection : []
        if !event.modifiers.contains(.shift) { model.clearSelection() }
    }

    func mouseDragged(_ event: ToolEvent) {
        guard let model else { return }
        if manipulator.isActive { manipulator.drag(event); return }
        guard let start = marqueeStart else { return }
        let rect = CGRect(
            x: min(start.x, event.point.x), y: min(start.y, event.point.y),
            width: abs(event.point.x - start.x), height: abs(event.point.y - start.y)
        )
        model.marquee = rect
        let inside = HitTesting.objects(intersecting: rect, in: model.document)
            .filter { !model.hiddenObjectIDs.contains($0) }
        model.select(marqueeBase + inside.filter { !marqueeBase.contains($0) })
    }

    func mouseUp(_ event: ToolEvent) {
        if manipulator.isActive { manipulator.end(event) }
        marqueeStart = nil
        model?.marquee = nil
    }

    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor {
        manipulator.cursor(at: point) ?? .arrow
    }

    func deactivate() {
        manipulator.cancel()
        model?.marquee = nil
    }
}
