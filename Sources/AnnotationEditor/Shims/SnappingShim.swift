import CoreGraphics

/// A guide line drawn while snapping, in base-image pixels.
struct SnapGuide: Equatable, Sendable {
    enum Axis: Sendable { case vertical, horizontal }
    var axis: Axis
    /// x for vertical guides, y for horizontal ones.
    var position: CGFloat
    /// Extent along the guide.
    var from: CGFloat
    var to: CGFloat
}

// TEMP until AnnotationKit provides snapping geometry.
// Edges and centres snap to the edges and centres of candidate rects
// (the image rect and other objects). Pure; unit-tested.
enum SnappingShim {
    struct Result: Equatable {
        var offset: CGVector
        var guides: [SnapGuide]
    }

    /// Snaps a moving rect: returns the correction to add and the guides to show.
    static func snap(moving rect: CGRect, candidates: [CGRect], tolerance: CGFloat) -> Result {
        let xs = [rect.minX, rect.midX, rect.maxX]
        let ys = [rect.minY, rect.midY, rect.maxY]
        let x = best(values: xs, targets: candidates.flatMap { [$0.minX, $0.midX, $0.maxX] }, tolerance: tolerance)
        let y = best(values: ys, targets: candidates.flatMap { [$0.minY, $0.midY, $0.maxY] }, tolerance: tolerance)
        let snapped = rect.offsetBy(dx: x ?? 0, dy: y ?? 0)
        return Result(
            offset: CGVector(dx: x ?? 0, dy: y ?? 0),
            guides: guides(for: snapped, candidates: candidates, snapX: x != nil, snapY: y != nil)
        )
    }

    /// Snaps a single point (a resize handle or crop edge).
    static func snap(point: CGPoint, candidates: [CGRect], tolerance: CGFloat) -> (CGPoint, [SnapGuide]) {
        let r = CGRect(origin: point, size: .zero)
        let res = snap(moving: r, candidates: candidates, tolerance: tolerance)
        return (CGPoint(x: point.x + res.offset.dx, y: point.y + res.offset.dy), res.guides)
    }

    private static func best(values: [CGFloat], targets: [CGFloat], tolerance: CGFloat) -> CGFloat? {
        var bestDelta: CGFloat?
        for v in values {
            for t in targets {
                let d = t - v
                if abs(d) <= tolerance, abs(d) < abs(bestDelta ?? .infinity) { bestDelta = d }
            }
        }
        return bestDelta
    }

    private static func guides(for r: CGRect, candidates: [CGRect], snapX: Bool, snapY: Bool) -> [SnapGuide] {
        var out: [SnapGuide] = []
        let eps: CGFloat = 0.5
        if snapX {
            for x in [r.minX, r.midX, r.maxX] {
                let matching = candidates.filter { c in [c.minX, c.midX, c.maxX].contains { abs($0 - x) < eps } }
                guard !matching.isEmpty else { continue }
                let lo = matching.map(\.minY).min().map { min($0, r.minY) } ?? r.minY
                let hi = matching.map(\.maxY).max().map { max($0, r.maxY) } ?? r.maxY
                out.append(SnapGuide(axis: .vertical, position: x, from: lo, to: hi))
            }
        }
        if snapY {
            for y in [r.minY, r.midY, r.maxY] {
                let matching = candidates.filter { c in [c.minY, c.midY, c.maxY].contains { abs($0 - y) < eps } }
                guard !matching.isEmpty else { continue }
                let lo = matching.map(\.minX).min().map { min($0, r.minX) } ?? r.minX
                let hi = matching.map(\.maxX).max().map { max($0, r.maxX) } ?? r.maxX
                out.append(SnapGuide(axis: .horizontal, position: y, from: lo, to: hi))
            }
        }
        return out
    }
}
