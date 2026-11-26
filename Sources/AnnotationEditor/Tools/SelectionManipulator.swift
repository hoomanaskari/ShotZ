import AnnotationKit
import CoreGraphics
import Foundation

/// Moves and resizes the selection. Shared by the Select tool and the drawing
/// tools (which manipulate an already-selected object before drawing a new one).
/// A whole drag is one undo step.
@MainActor final class SelectionManipulator {
    private enum Mode {
        case move(originals: [AnnotationObject], start: CGPoint, bounds: CGRect, duplicate: Bool)
        case resize(original: AnnotationObject, handle: Handle.Kind, grab: CGVector)
    }

    private weak var model: EditorModel?
    private var mode: Mode?
    private var started = false
    private var downPoint: CGPoint = .zero

    init(model: EditorModel?) {
        self.model = model
    }

    var isActive: Bool { mode != nil }

    /// Starts a manipulation if `event` hits a handle or a selected object.
    /// `allowMove` false limits it to handles.
    @discardableResult
    func begin(_ event: ToolEvent, allowMove: Bool = true) -> Bool {
        guard let model else { return false }
        downPoint = event.point
        started = false
        if let (id, handle) = model.hitHandle(at: event.point), let object = model.document[id: id] {
            mode = .resize(
                original: object, handle: handle.kind,
                grab: CGVector(dx: handle.position.x - event.point.x, dy: handle.position.y - event.point.y)
            )
            return true
        }
        guard allowMove, let hit = model.hitObject(at: event.point), model.selection.contains(hit) else { return false }
        beginMove(event)
        return true
    }

    /// Starts moving the current selection from `event`.
    func beginMove(_ event: ToolEvent) {
        guard let model else { return }
        downPoint = event.point
        started = false
        let originals = model.selectedObjects
        let bounds = originals.map(model.frame(of:)).reduce(CGRect.null) { $0.union($1) }
        mode = .move(originals: originals, start: event.point, bounds: bounds, duplicate: event.modifiers.contains(.option))
    }

    func drag(_ event: ToolEvent) {
        guard let model, let mode else { return }
        if !started {
            guard hypot(event.point.x - downPoint.x, event.point.y - downPoint.y) >= model.dragThreshold else { return }
            started = true
            startInteractiveChange(mode)
        }
        switch self.mode {
        case .move(let originals, let start, let bounds, _):
            var d = CGVector(dx: event.point.x - start.x, dy: event.point.y - start.y)
            if event.modifiers.contains(.shift) { d = AngleSnapping.axisConstrained(d) }
            let ids = Set(model.selection)
            let snap = model.snapOffset(for: bounds.offsetBy(dx: d.dx, dy: d.dy), excluding: ids, modifiers: event.modifiers)
            if event.modifiers.contains(.shift) {
                if d.dx == 0 { d.dy += snap.dy } else { d.dx += snap.dx }
            } else {
                d.dx += snap.dx; d.dy += snap.dy
            }
            model.store.updateInteractive { doc in
                for original in originals {
                    doc[id: original.id] = ObjectGeometry.moved(original, by: d)
                }
            }
        case .resize(let original, let handle, let grab):
            var p = CGPoint(x: event.point.x + grab.dx, y: event.point.y + grab.dy)
            p = model.snapPoint(p, excluding: [original.id], modifiers: event.modifiers)
            var mods: TransformModifiers = []
            if event.modifiers.contains(.shift) { mods.insert(.constrain) }
            if event.modifiers.contains(.option) { mods.insert(.fromCenter) }
            let resized = ObjectGeometry.resized(original, handle: handle, to: p, modifiers: mods)
            model.store.updateInteractive { doc in doc[id: original.id] = resized }
        case nil:
            break
        }
    }

    private func startInteractiveChange(_ mode: Mode) {
        guard let model else { return }
        switch mode {
        case .move(let originals, let start, let bounds, let duplicate):
            if duplicate {
                // ⌥-drag: the copies move, the originals stay.
                model.store.beginInteractiveChange(String(localized: "Duplicate"))
                let copies = originals.map { $0.duplicated() }
                model.store.updateInteractive { doc in doc.objects.append(contentsOf: copies) }
                model.select(copies.map(\.id))
                self.mode = .move(originals: copies, start: start, bounds: bounds, duplicate: false)
            } else {
                model.store.beginInteractiveChange(String(localized: "Move"))
            }
        case .resize:
            model.store.beginInteractiveChange(String(localized: "Resize"))
        }
    }

    func end(_ event: ToolEvent) {
        guard let model else { return }
        if started { model.store.commitInteractiveChange() }
        model.guides = []
        mode = nil
        started = false
    }

    /// True if the last drag actually changed something.
    var didDrag: Bool { started }

    func cancel() {
        if started { model?.store.cancelInteractiveChange() }
        model?.guides = []
        mode = nil
        started = false
    }

    /// Cursor for hovering `point` (handles and selected bodies).
    func cursor(at point: CGPoint) -> ToolCursor? {
        guard let model else { return nil }
        if let (id, handle) = model.hitHandle(at: point), let object = model.document[id: id] {
            let c = ObjectGeometry.frame(of: object)
            return .resize(angle: atan2(handle.position.y - c.midY, handle.position.x - c.midX))
        }
        if let hit = model.hitObject(at: point), model.selection.contains(hit) { return .move }
        return nil
    }
}
