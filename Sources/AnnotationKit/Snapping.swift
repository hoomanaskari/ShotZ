import CoreGraphics

/// A guide line to show while snapped, in base-image pixels.
public struct SnapGuide: Sendable, Equatable, Hashable {
    public enum Axis: Sendable, Hashable {
        /// A vertical line at x = `position`, from y = `start` to `end`.
        case vertical
        /// A horizontal line at y = `position`, from x = `start` to `end`.
        case horizontal
    }

    public var axis: Axis
    public var position: CGFloat
    public var start: CGFloat
    public var end: CGFloat

    public init(axis: Axis, position: CGFloat, start: CGFloat, end: CGFloat) {
        self.axis = axis
        self.position = position
        self.start = start
        self.end = end
    }
}

/// Lines objects can snap to. Build once when a drag begins (`Snapping.targets`), reuse per mouse move.
public struct SnapTargets: Sendable, Equatable {
    struct Line: Sendable, Equatable {
        var value: CGFloat
        /// Extent of the source along the other axis, for drawing the guide.
        var spanStart: CGFloat
        var spanEnd: CGFloat
    }

    var xs: [Line] = []
    var ys: [Line] = []

    public var isEmpty: Bool { xs.isEmpty && ys.isEmpty }

    /// Adds edges and centre of `rect` as targets.
    public mutating func add(_ rect: CGRect) {
        let r = rect.standardized
        for x in [r.minX, r.midX, r.maxX] { xs.append(Line(value: x, spanStart: r.minY, spanEnd: r.maxY)) }
        for y in [r.minY, r.midY, r.maxY] { ys.append(Line(value: y, spanStart: r.minX, spanEnd: r.maxX)) }
    }
}

public struct SnapResult: Sendable, Equatable {
    /// Add this to the proposed position.
    public var offset: CGVector
    public var guides: [SnapGuide]
}

/// Snapping of object edges/centres to the image and to other objects (SPEC §5.2).
/// ⌘ disables snapping: the editor simply doesn't call it.
public enum Snapping {
    /// Default threshold in screen points; convert to image pixels by dividing by the zoom.
    public static let defaultThresholdPoints: CGFloat = 6

    /// Targets: the visible image (crop) edges and centre, plus every object not in `excluding`.
    public static func targets(in document: AnnotationDocument, excluding: Set<AnnotationObject.ID> = []) -> SnapTargets {
        var t = SnapTargets()
        t.add(document.imageRect)
        for object in document.objects where !excluding.contains(object.id) {
            t.add(ObjectGeometry.frame(of: object))
        }
        return t
    }

    /// Snaps a moving frame (edges and centre on each axis independently).
    public static func snap(frame: CGRect, to targets: SnapTargets, threshold: CGFloat) -> SnapResult {
        let f = frame.standardized
        let x = best([f.minX, f.midX, f.maxX], targets.xs, threshold)
        let y = best([f.minY, f.midY, f.maxY], targets.ys, threshold)
        let moved = f.offsetBy(dx: x?.delta ?? 0, dy: y?.delta ?? 0)
        var guides: [SnapGuide] = []
        if let x {
            guides += x.lines.map { SnapGuide(axis: .vertical, position: $0.value,
                                              start: min($0.spanStart, moved.minY), end: max($0.spanEnd, moved.maxY)) }
        }
        if let y {
            guides += y.lines.map { SnapGuide(axis: .horizontal, position: $0.value,
                                              start: min($0.spanStart, moved.minX), end: max($0.spanEnd, moved.maxX)) }
        }
        return SnapResult(offset: CGVector(dx: x?.delta ?? 0, dy: y?.delta ?? 0), guides: guides)
    }

    /// Snaps a single point (a dragged handle, a crop corner, a new object's corner).
    public static func snap(point: CGPoint, to targets: SnapTargets, threshold: CGFloat) -> (point: CGPoint, guides: [SnapGuide]) {
        let r = snap(frame: CGRect(origin: point, size: .zero), to: targets, threshold: threshold)
        return (CGPoint(x: point.x + r.offset.dx, y: point.y + r.offset.dy), r.guides)
    }

    /// The smallest correction within `threshold` and every target line that matches it.
    private static func best(_ values: [CGFloat], _ lines: [SnapTargets.Line], _ threshold: CGFloat)
        -> (delta: CGFloat, lines: [SnapTargets.Line])? {
        var bestDelta: CGFloat?
        for v in values {
            for l in lines {
                let d = l.value - v
                if abs(d) <= threshold, bestDelta.map({ abs(d) < abs($0) }) ?? true { bestDelta = d }
            }
        }
        guard let delta = bestDelta else { return nil }
        // Every line that coincides after the correction gets a guide (deduplicated by position).
        var matched: [CGFloat: SnapTargets.Line] = [:]
        for v in values {
            for l in lines where abs(l.value - (v + delta)) < 0.5 {
                if var m = matched[l.value] {
                    m.spanStart = min(m.spanStart, l.spanStart)
                    m.spanEnd = max(m.spanEnd, l.spanEnd)
                    matched[l.value] = m
                } else {
                    matched[l.value] = l
                }
            }
        }
        return (delta, matched.values.sorted { $0.value < $1.value })
    }
}
