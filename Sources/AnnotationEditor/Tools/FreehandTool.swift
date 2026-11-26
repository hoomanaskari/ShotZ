import AnnotationKit
import CoreGraphics

/// Pen (P) and the freehand highlighter: smoothed on release, one object
/// per stroke. ⇧ draws a straight line.
@MainActor final class FreehandTool: DrawingTool {
    private var points: [CGPoint] = []

    override func makeShape(from start: CGPoint, to current: CGPoint, modifiers: ToolModifiers) -> AnnotationObject.Shape? {
        guard let model else { return nil }
        if points.isEmpty { points = [start] }
        if modifiers.contains(.shift) {
            points = [start, current]
        } else if let last = points.last, hypot(current.x - last.x, current.y - last.y) >= 0.75 / max(model.pointsPerPixel, 0.0001) {
            points.append(current)
        }
        return shape(points)
    }

    private func shape(_ pts: [CGPoint]) -> AnnotationObject.Shape {
        kind == .highlighter ? .highlight(.freehand(pts)) : .pen(pts)
    }

    override func finalize(_ object: AnnotationObject) -> AnnotationObject? {
        defer { points = [] }
        guard let model, points.count >= 2 else { return nil }
        let tolerance = max(0.6 / max(model.pointsPerPixel, 0.0001), object.style.lineWidth * 0.08)
        var o = object
        o.shape = shape(points.count > 2 ? StrokeSmoothingShim.smooth(points, tolerance: tolerance) : points)
        return o
    }

    override func deactivate() {
        points = []
        super.deactivate()
    }
}

/// H: freehand marker or rectangle highlight, per the tool's option.
@MainActor final class HighlighterTool: Tool, ModelBound {
    let kind = ToolKind.highlighter
    weak var model: EditorModel? { didSet { freehand.model = model; rect.model = model } }
    private let freehand = FreehandTool(kind: .highlighter)
    private let rect = ShapeTool(kind: .highlighter)
    private var active: DrawingTool?

    private var current: DrawingTool {
        (model?.settings(for: .highlighter).highlightRect ?? false) ? rect : freehand
    }

    func mouseDown(_ event: ToolEvent) {
        active = current
        active?.mouseDown(event)
    }

    func mouseDragged(_ event: ToolEvent) { active?.mouseDragged(event) }

    func mouseUp(_ event: ToolEvent) {
        active?.mouseUp(event)
        active = nil
    }

    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor {
        current.cursor(at: point, modifiers: modifiers)
    }

    func deactivate() {
        freehand.deactivate()
        rect.deactivate()
    }
}
