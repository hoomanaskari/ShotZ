import AnnotationKit
import CoreGraphics

/// Drag-to-create tools: arrow, rectangle, ellipse, line, blur/pixelate,
/// and the rectangle highlighter.
/// ⇧ squares boxes / snaps lines to 15°; ⌥ draws boxes from the centre.
@MainActor final class ShapeTool: DrawingTool {
    override func makeShape(from start: CGPoint, to current: CGPoint, modifiers: ToolModifiers) -> AnnotationObject.Shape? {
        guard let model else { return nil }
        let s = model.settings(for: kind)
        switch kind {
        case .arrow:
            let end = modifiers.contains(.shift) ? HandleGeometryShim.snapAngle(current, around: start) : current
            let control = s.arrowStyle == .curved ? ArrowCurve.defaultControl(start: start, end: end) : nil
            return .arrow(ArrowGeometry(start: start, end: end, control: control, style: s.arrowStyle))
        case .line:
            let end = modifiers.contains(.shift) ? HandleGeometryShim.snapAngle(current, around: start) : current
            return .line(start: start, end: end)
        case .rectangle:
            return .rectangle(Self.box(start, current, modifiers), cornerRadius: s.cornerRadiusUnits * model.unit)
        case .ellipse:
            return .ellipse(Self.box(start, current, modifiers))
        case .redact:
            return .redact(Self.box(start, current, modifiers), s.redactMode)
        case .highlighter:
            return .highlight(.rect(Self.box(start, current, modifiers)))
        default:
            return nil
        }
    }

    override func finalize(_ object: AnnotationObject) -> AnnotationObject? {
        guard let model else { return object }
        let minSize = model.dragThreshold
        switch object.shape {
        case .arrow(let g):
            return hypot(g.end.x - g.start.x, g.end.y - g.start.y) >= minSize ? object : nil
        case .line(let s, let e):
            return hypot(e.x - s.x, e.y - s.y) >= minSize ? object : nil
        case .rectangle(let r, _), .ellipse(let r), .redact(let r, _), .highlight(.rect(let r)):
            return r.width >= minSize || r.height >= minSize ? object : nil
        default:
            return object
        }
    }

    /// The box between two points: ⇧ square, ⌥ from centre.
    static func box(_ a: CGPoint, _ b: CGPoint, _ modifiers: ToolModifiers) -> CGRect {
        var dx = b.x - a.x, dy = b.y - a.y
        if modifiers.contains(.shift) {
            let side = max(abs(dx), abs(dy))
            dx = dx < 0 ? -side : side
            dy = dy < 0 ? -side : side
        }
        if modifiers.contains(.option) {
            return CGRect(x: a.x - abs(dx), y: a.y - abs(dy), width: 2 * abs(dx), height: 2 * abs(dy))
        }
        return CGRect(x: a.x, y: a.y, width: dx, height: dy).standardized
    }
}
