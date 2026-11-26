import AnnotationKit
import CoreGraphics
import Foundation

/// Shared behaviour of the drawing tools (SPEC §5.2):
/// - dragging a handle or the body of an already-selected object edits it;
/// - a plain click (no drag) on an existing object selects it;
/// - otherwise a drag creates a new object, which is selected afterwards;
/// - the tool stays armed (or returns to Select, per setting).
@MainActor class DrawingTool: Tool, ModelBound {
    let kind: ToolKind
    weak var model: EditorModel? { didSet { manipulator = SelectionManipulator(model: model) } }
    private(set) var manipulator = SelectionManipulator(model: nil)

    private(set) var start: CGPoint?
    private var clickedObject: AnnotationObject.ID?
    private(set) var creatingID: AnnotationObject.ID?

    init(kind: ToolKind) {
        self.kind = kind
    }

    // MARK: Subclass hooks

    /// The shape for a drag from `start` to `current`; nil = too small yet.
    func makeShape(from start: CGPoint, to current: CGPoint, modifiers: ToolModifiers) -> AnnotationObject.Shape? { nil }
    /// Called on mouse down when creating, before any drag. Return true to create immediately (counter).
    func createsOnMouseDown() -> Bool { false }
    /// Whether a plain click on `object` selects it (instead of creating).
    func selectsOnClick(_ object: AnnotationObject) -> Bool { true }
    func actionName() -> String { String(localized: "Add \(kind.title)") }
    /// Last chance to adjust the object when the drag ends (smoothing).
    func finalize(_ object: AnnotationObject) -> AnnotationObject? { object }
    func style() -> ObjectStyle { model?.style(for: kind) ?? .default }

    // MARK: Tool

    func mouseDown(_ event: ToolEvent) {
        guard let model else { return }
        if model.textHost?.isEditingText == true { model.textHost?.endEditing() }
        if manipulator.begin(event) { return }
        start = event.point
        clickedObject = model.hitObject(at: event.point).flatMap { id in
            model.document[id: id].flatMap { selectsOnClick($0) ? id : nil }
        }
        if createsOnMouseDown(), clickedObject == nil { create(to: event.point, modifiers: event.modifiers) }
    }

    func mouseDragged(_ event: ToolEvent) {
        guard let model else { return }
        if manipulator.isActive { manipulator.drag(event); return }
        guard let start else { return }
        if creatingID == nil {
            guard hypot(event.point.x - start.x, event.point.y - start.y) >= model.dragThreshold else { return }
            clickedObject = nil
        }
        create(to: event.point, modifiers: event.modifiers)
    }

    /// Creates the object on first call, updates it afterwards.
    func create(to point: CGPoint, modifiers: ToolModifiers) {
        guard let model, let start else { return }
        guard let shape = makeShape(from: start, to: point, modifiers: modifiers) else { return }
        if let id = creatingID {
            model.store.updateInteractive { doc in doc[id: id]?.shape = shape }
        } else {
            let object = AnnotationObject(shape: shape, style: style())
            creatingID = object.id
            model.store.beginInteractiveChange(actionName())
            model.store.updateInteractive { doc in doc.objects.append(object) }
            model.select([object.id])
        }
    }

    func mouseUp(_ event: ToolEvent) {
        guard let model else { return }
        defer { start = nil; clickedObject = nil; creatingID = nil; model.guides = [] }
        if manipulator.isActive {
            let dragged = manipulator.didDrag
            manipulator.end(event)
            if !dragged, let hit = model.hitObject(at: event.point) { model.select([hit]) }
            return
        }
        if let id = creatingID {
            if let object = model.document[id: id] {
                if let final = finalize(object) {
                    if final != object { model.store.updateInteractive { doc in doc[id: id] = final } }
                    model.store.commitInteractiveChange()
                    model.select([id])
                    model.didFinishDrawing()
                } else {
                    model.store.cancelInteractiveChange()
                    model.clearSelection()
                }
            }
            return
        }
        if let hit = clickedObject {
            model.select([hit])
        } else {
            model.clearSelection()
        }
    }

    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor {
        manipulator.cursor(at: point) ?? .crosshair
    }

    func deactivate() {
        manipulator.cancel()
        if creatingID != nil { model?.store.cancelInteractiveChange() }
        start = nil; creatingID = nil
    }
}
