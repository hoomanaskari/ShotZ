import CoreGraphics

/// The drawable pieces of an arrow: a stroked shaft (round caps) and filled shapes
/// (heads, dot, tapered body). Built once per draw; also used for bounds and hit testing.
struct ArrowPath {
    /// Centre line, stroked with `shaftWidth`. nil for tapered arrows (the body is a fill).
    var shaft: CGPath?
    var shaftWidth: CGFloat
    /// Closed shapes to fill (and to stroke with `fillRounding` for softened corners).
    var fills: [CGPath]
    /// Stroke width applied to fills with round joins so tips are slightly rounded.
    var fillRounding: CGFloat

    /// Head proportions relative to the line width.
    struct HeadMetrics {
        var length: CGFloat
        var halfWidth: CGFloat
        /// How far the back of the head is notched in, as a fraction of `length`.
        var notch: CGFloat
    }

    /// Head size grows sub-linearly with the line width: thin lines get proportionally larger
    /// heads (≈ 6.8 × w at 3.6 px) so they stay legible, thick lines proportionally smaller ones
    /// (≈ 4.1 × w at 29 px) so they don't turn into blunt wedges. Half-angle ≈ 27°.
    static func headMetrics(width w: CGFloat, style: ArrowStyle, arrowLength: CGFloat) -> HeadMetrics {
        var length = 2.6 * w + 8 * w.squareRoot()
        var halfWidth = length * 0.5
        if style == .tapered {
            length *= 1.12
            halfWidth = length * 0.56
        }
        // Short arrows: the head(s) never take more than 45 % of the arrow (30 % each for two).
        let maxLength = max(arrowLength * (style == .doubleHeaded ? 0.3 : 0.45), 1)
        if length > maxLength {
            let k = maxLength / length
            length *= k
            halfWidth *= k
        }
        return HeadMetrics(length: length, halfWidth: halfWidth, notch: 0.24)
    }

    private struct Head {
        var path: CGPath
        /// Where the shaft meets the head (inside the notch).
        var join: CGPoint
        /// Unit vector from the head's base towards its tip.
        var axis: CGVector
    }

    static func make(_ g: ArrowGeometry, width rawWidth: CGFloat) -> ArrowPath {
        var w = max(rawWidth, 0.5)
        let p0 = g.start, p2 = g.end, c = g.bezierControl
        let chord = max(Geometry.distance(p0, p2), 0.001)
        let m = headMetrics(width: w, style: g.style, arrowLength: chord)
        // A head shrunk to fit a very short arrow must still read as a head: the shaft narrows
        // with it so the head stays at least ~3× the shaft width (never a stub or a pill).
        w = min(w, max(m.halfWidth / 1.6, 0.5))

        // The tip is exactly the endpoint; the axis is the chord from the spine point one head
        // length back, so the head sits on the curve rather than on the end tangent.
        func head(atEnd: Bool) -> Head {
            let tipT: CGFloat = atEnd ? 1 : 0
            let tip = atEnd ? p2 : p0
            let backT = Geometry.quadParameter(p0, c, p2, distance: m.length, from: tipT, towards: atEnd ? 0 : 1)
            let axis = Geometry.unit(from: Geometry.quad(p0, c, p2, backT), to: tip)
            let n = Geometry.normal(axis)
            let base = Geometry.offset(tip, axis, -m.length)
            let notch = Geometry.offset(base, axis, m.length * m.notch)
            let path = CGMutablePath()
            path.move(to: tip)
            path.addLine(to: Geometry.offset(base, n, m.halfWidth))
            path.addLine(to: notch)
            path.addLine(to: Geometry.offset(base, n, -m.halfWidth))
            path.closeSubpath()
            return Head(path: path, join: Geometry.offset(notch, axis, min(w * 0.3, m.length * 0.1)), axis: axis)
        }

        var fills: [CGPath] = []
        let endHead = head(atEnd: true)
        fills.append(endHead.path)
        var startHead: Head?
        switch g.style {
        case .doubleHeaded:
            let h = head(atEnd: false)
            fills.append(h.path)
            startHead = h
        case .lineWithDot:
            let r = max(w * 0.9 + 2.5, w / 2 + 2.5)
            fills.append(CGPath(ellipseIn: CGRect(x: p0.x - r, y: p0.y - r, width: 2 * r, height: 2 * r), transform: nil))
        case .straight, .curved, .tapered:
            break
        }
        let rounding = min(w * 0.2, m.length * 0.06)
        let spine = spinePath(p0, c, p2, end: endHead, start: startHead, blend: m.length * 1.7)
        if g.style == .tapered {
            fills.insert(taperedBody(along: spine, tailWidth: w * 0.45, headWidth: w * 2.1), at: 0)
            return ArrowPath(shaft: nil, shaftWidth: w, fills: fills, fillRounding: rounding)
        }
        return ArrowPath(shaft: spine, shaftWidth: w, fills: fills, fillRounding: rounding)
    }

    private static func tangent(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGVector {
        let v = CGVector(dx: 2 * (1 - t) * (c.x - p0.x) + 2 * t * (p2.x - c.x), dy: 2 * (1 - t) * (c.y - p0.y) + 2 * t * (p2.y - c.y))
        let len = hypot(v.dx, v.dy)
        return len > 1e-9 ? CGVector(dx: v.dx / len, dy: v.dy / len) : Geometry.unit(from: p0, to: p2)
    }

    /// The shaft's centre line: the curve itself for most of its length, then a cubic that leaves
    /// the curve tangentially and arrives along the head's axis, so there's no kink where shaft
    /// meets head on curved arrows. For straight spines every piece is collinear.
    private static func spinePath(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, end: Head, start: Head?, blend: CGFloat) -> CGPath {
        var tEnd = Geometry.quadParameter(p0, c, p2, distance: blend, from: 1, towards: 0)
        var tStart: CGFloat = start == nil ? 0 : Geometry.quadParameter(p0, c, p2, distance: blend, from: 0, towards: 1)
        let path = CGMutablePath()
        let first = start?.join ?? p0
        path.move(to: first)
        if tStart >= tEnd {
            // Too short for a curved middle: one cubic from start to head.
            tStart = (tStart + tEnd) / 2
            tEnd = tStart
        }
        func blendCurve(from a: CGPoint, leaving da: CGVector, to b: CGPoint, arriving db: CGVector) {
            let k = Geometry.distance(a, b) / 3
            path.addCurve(to: b, control1: Geometry.offset(a, da, k), control2: Geometry.offset(b, db, -k))
        }
        if let start {
            let q = Geometry.quad(p0, c, p2, tStart)
            blendCurve(from: start.join, leaving: CGVector(dx: -start.axis.dx, dy: -start.axis.dy), to: q, arriving: tangent(p0, c, p2, tStart))
        } else if tStart > 0 {
            path.addLine(to: Geometry.quad(p0, c, p2, tStart))
        }
        if tEnd > tStart {
            let (_, cc, b) = Geometry.quadSegment(p0, c, p2, tStart, tEnd)
            path.addQuadCurve(to: b, control: cc)
        }
        let q = Geometry.quad(p0, c, p2, tEnd)
        let leaving = tEnd <= 0 && start == nil ? Geometry.unit(from: p0, to: end.join) : tangent(p0, c, p2, tEnd)
        blendCurve(from: q, leaving: leaving, to: end.join, arriving: end.axis)
        return path
    }

    /// A filled body that widens from a rounded tail to the head, following the spine.
    private static func taperedBody(along spine: CGPath, tailWidth: CGFloat, headWidth: CGFloat) -> CGPath {
        let pts = flatten(spine)
        let path = CGMutablePath()
        guard pts.count >= 2 else { return path }
        var lengths: [CGFloat] = [0]
        for i in 1..<pts.count { lengths.append(lengths[i - 1] + Geometry.distance(pts[i - 1], pts[i])) }
        let total = max(lengths[lengths.count - 1], 0.001)
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in pts.indices {
            let a = pts[max(i - 1, 0)], b = pts[min(i + 1, pts.count - 1)]
            let n = Geometry.normal(Geometry.unit(from: a, to: b))
            let f = lengths[i] / total
            // Ease the widening so the body reads as a pointer, not a wedge.
            let half = (tailWidth + (headWidth - tailWidth) * (f * (2 - f) * 0.6 + f * 0.4)) / 2
            left.append(Geometry.offset(pts[i], n, half))
            right.append(Geometry.offset(pts[i], n, -half))
        }
        path.addLines(between: left)
        for p in right.reversed() { path.addLine(to: p) }
        // Round tail cap.
        let tailDir = Geometry.unit(from: pts[1], to: pts[0])
        path.addQuadCurve(to: left[0], control: Geometry.offset(pts[0], tailDir, tailWidth))
        path.closeSubpath()
        return path
    }

    /// Points along a path of lines, quads and cubics (24 samples per curve).
    private static func flatten(_ path: CGPath) -> [CGPoint] {
        var pts: [CGPoint] = []
        path.applyWithBlock { element in
            let e = element.pointee
            let last = pts.last ?? .zero
            switch e.type {
            case .moveToPoint, .addLineToPoint:
                pts.append(e.points[0])
            case .addQuadCurveToPoint:
                let c = e.points[0], p = e.points[1]
                for i in 1...24 { pts.append(Geometry.quad(last, c, p, CGFloat(i) / 24)) }
            case .addCurveToPoint:
                let c1 = e.points[0], c2 = e.points[1], p = e.points[2]
                for i in 1...24 {
                    let t = CGFloat(i) / 24, u = 1 - t
                    pts.append(CGPoint(x: u * u * u * last.x + 3 * u * u * t * c1.x + 3 * u * t * t * c2.x + t * t * t * p.x,
                                       y: u * u * u * last.y + 3 * u * u * t * c1.y + 3 * u * t * t * c2.y + t * t * t * p.y))
                }
            case .closeSubpath:
                break
            @unknown default:
                break
            }
        }
        // Drop coincident neighbours (a zero-length step has no direction).
        var out: [CGPoint] = []
        for p in pts where out.last.map({ Geometry.distance($0, p) > 0.01 }) ?? true { out.append(p) }
        return out
    }

    /// Every piece as one fillable silhouette list (shaft converted to its stroke outline).
    func silhouettes(extraWidth: CGFloat = 0) -> [CGPath] {
        var out: [CGPath] = []
        if let shaft, !shaft.isEmpty {
            out.append(shaft.copy(strokingWithWidth: shaftWidth + extraWidth, lineCap: .round, lineJoin: .round, miterLimit: 10))
        }
        for f in fills {
            if extraWidth + fillRounding > 0 {
                out.append(f.copy(strokingWithWidth: extraWidth + fillRounding, lineCap: .round, lineJoin: .round, miterLimit: 10))
            }
            out.append(f)
        }
        return out
    }

    func boundingBox(extraWidth: CGFloat = 0) -> CGRect {
        var r = CGRect.null
        if let shaft, !shaft.isEmpty {
            r = r.union(shaft.boundingBoxOfPath.insetBy(dx: -(shaftWidth + extraWidth) / 2, dy: -(shaftWidth + extraWidth) / 2))
        }
        let pad = (fillRounding + extraWidth) / 2
        for f in fills { r = r.union(f.boundingBoxOfPath.insetBy(dx: -pad, dy: -pad)) }
        return r
    }
}
