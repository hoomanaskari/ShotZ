import CoreGraphics

/// ⇧ constraints (SPEC §5.2): lines and arrows snap to 15° steps.
public enum AngleSnapping {
    public static let defaultStep: CGFloat = 15

    /// `point` rotated about `origin` onto the nearest multiple of `stepDegrees`, keeping its distance.
    public static func snap(_ point: CGPoint, around origin: CGPoint, stepDegrees: CGFloat = defaultStep) -> CGPoint {
        let d = Geometry.distance(origin, point)
        guard d > 0, stepDegrees > 0 else { return point }
        let step = stepDegrees * .pi / 180
        let angle = (atan2(point.y - origin.y, point.x - origin.x) / step).rounded() * step
        // Round tiny floating error so 0°/90° come out exactly axis-aligned.
        func clean(_ v: CGFloat) -> CGFloat { abs(v) < 1e-9 ? 0 : v }
        return CGPoint(x: origin.x + clean(cos(angle)) * d, y: origin.y + clean(sin(angle)) * d)
    }

    /// ⇧ while moving: keeps only the dominant axis of a drag.
    public static func axisConstrained(_ delta: CGVector) -> CGVector {
        abs(delta.dx) >= abs(delta.dy) ? CGVector(dx: delta.dx, dy: 0) : CGVector(dx: 0, dy: delta.dy)
    }
}
