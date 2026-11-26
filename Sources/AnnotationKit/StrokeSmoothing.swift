import CoreGraphics

/// Freehand stroke processing for the pen and highlighter (SPEC §5.3). The editor calls
/// `smooth` on mouse-up and stores the result; the renderer always draws stored points
/// as a Catmull-Rom curve via `path(through:)`, so live strokes and final strokes match.
public enum StrokeSmoothing {
    /// Cleans raw mouse samples: drops jitter closer than `minDistance`, relaxes the
    /// polyline (endpoints fixed), then simplifies to remove redundant points.
    /// - Parameter minDistance: in image pixels; pass about 1–2 screen points at the current zoom.
    public static func smooth(_ points: [CGPoint], minDistance: CGFloat = 2, iterations: Int = 2) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var pts: [CGPoint] = [points[0]]
        for p in points.dropFirst() where Geometry.distance(p, pts[pts.count - 1]) >= minDistance {
            pts.append(p)
        }
        if let last = points.last, pts.last != last {
            if pts.count > 1, Geometry.distance(last, pts[pts.count - 1]) < minDistance { pts[pts.count - 1] = last } else { pts.append(last) }
        }
        guard pts.count > 2 else { return pts }
        for _ in 0..<max(iterations, 0) {
            var next = pts
            for i in 1..<(pts.count - 1) {
                next[i] = CGPoint(x: pts[i - 1].x * 0.25 + pts[i].x * 0.5 + pts[i + 1].x * 0.25,
                                  y: pts[i - 1].y * 0.25 + pts[i].y * 0.5 + pts[i + 1].y * 0.25)
            }
            pts = next
        }
        return simplify(pts, epsilon: minDistance * 0.25)
    }

    /// ⇧ straightens: the stroke becomes a segment from first to last point.
    public static func straightened(_ points: [CGPoint]) -> [CGPoint] {
        guard let first = points.first, let last = points.last else { return points }
        return [first, last]
    }

    /// Ramer–Douglas–Peucker simplification.
    public static func simplify(_ points: [CGPoint], epsilon: CGFloat) -> [CGPoint] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true; keep[points.count - 1] = true
        var stack = [(0, points.count - 1)]
        while let (a, b) = stack.popLast() {
            guard b > a + 1 else { continue }
            var maxD: CGFloat = 0, index = a
            for i in (a + 1)..<b {
                let d = Geometry.distanceToSegment(points[i], points[a], points[b])
                if d > maxD { maxD = d; index = i }
            }
            if maxD > epsilon {
                keep[index] = true
                stack.append((a, index)); stack.append((index, b))
            }
        }
        return points.indices.filter { keep[$0] }.map { points[$0] }
    }

    /// A smooth path through every point (uniform Catmull-Rom as cubic Béziers).
    public static func path(through points: [CGPoint]) -> CGPath {
        let path = CGMutablePath()
        guard let first = points.first else { return path }
        path.move(to: first)
        guard points.count > 1 else {
            path.addLine(to: first)
            return path
        }
        if points.count == 2 {
            path.addLine(to: points[1])
            return path
        }
        for i in 0..<(points.count - 1) {
            let p0 = points[max(i - 1, 0)], p1 = points[i], p2 = points[i + 1], p3 = points[min(i + 2, points.count - 1)]
            let c1 = CGPoint(x: p1.x + (p2.x - p0.x) / 6, y: p1.y + (p2.y - p0.y) / 6)
            let c2 = CGPoint(x: p2.x - (p3.x - p1.x) / 6, y: p2.y - (p3.y - p1.y) / 6)
            path.addCurve(to: p2, control1: c1, control2: c2)
        }
        return path
    }
}
