import CoreGraphics

// TEMP until AnnotationKit provides stroke smoothing.
// Ramer–Douglas–Peucker simplification followed by Chaikin corner cutting.
// Pure; unit-tested.
enum StrokeSmoothingShim {
    static func smooth(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var simplified = simplify(points, tolerance: tolerance)
        for _ in 0..<2 { simplified = chaikin(simplified) }
        return simplified
    }

    static func simplify(_ points: [CGPoint], tolerance: CGFloat) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var maxDistance: CGFloat = 0
        var index = 0
        for i in 1..<(points.count - 1) {
            let d = distance(points[i], toSegment: first, last)
            if d > maxDistance { maxDistance = d; index = i }
        }
        guard maxDistance > tolerance else { return [first, last] }
        let left = simplify(Array(points[...index]), tolerance: tolerance)
        let right = simplify(Array(points[index...]), tolerance: tolerance)
        return left.dropLast() + right
    }

    /// One Chaikin pass; keeps the end points.
    static func chaikin(_ points: [CGPoint]) -> [CGPoint] {
        guard points.count > 2, let first = points.first, let last = points.last else { return points }
        var out = [first]
        for i in 0..<(points.count - 1) {
            let a = points[i], b = points[i + 1]
            out.append(CGPoint(x: 0.75 * a.x + 0.25 * b.x, y: 0.75 * a.y + 0.25 * b.y))
            out.append(CGPoint(x: 0.25 * a.x + 0.75 * b.x, y: 0.25 * a.y + 0.75 * b.y))
        }
        out.append(last)
        return out
    }

    static func distance(_ p: CGPoint, toSegment a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 0 else { return hypot(p.x - a.x, p.y - a.y) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return hypot(p.x - (a.x + t * dx), p.y - (a.y + t * dy))
    }
}
