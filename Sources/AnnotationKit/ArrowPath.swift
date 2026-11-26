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

    static func headMetrics(width w: CGFloat, style: ArrowStyle, arrowLength: CGFloat) -> HeadMetrics {
        var length = w * 3.3 + 5
        var halfWidth = length * 0.56
        if style == .tapered {
            length = w * 4.2 + 6
            halfWidth = length * 0.62
        }
        // Short arrows: keep the head under ~55 % of the arrow (two heads share the length).
        let heads: CGFloat = style == .doubleHeaded ? 2 : 1
        let maxLength = max(arrowLength * 0.55 / heads, 1)
        if length > maxLength {
            let k = maxLength / length
            length *= k
            halfWidth *= k
        }
        return HeadMetrics(length: length, halfWidth: halfWidth, notch: 0.24)
    }

    static func make(_ g: ArrowGeometry, width rawWidth: CGFloat) -> ArrowPath {
        let w = max(rawWidth, 0.5)
        let p0 = g.start, p2 = g.end, c = g.bezierControl
        let chord = max(Geometry.distance(p0, p2), 0.001)
        let m = headMetrics(width: w, style: g.style, arrowLength: chord)
        var fills: [CGPath] = []

        // Each head sits on the spine: the tip is the endpoint, the axis points from the spine
        // point one head-length back towards the tip (a chord, which looks right on curves).
        func head(atEnd: Bool) -> (path: CGPath, cutT: CGFloat) {
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
            let cutT = Geometry.quadParameter(p0, c, p2, distance: m.length * (1 - m.notch) - w * 0.15,
                                              from: tipT, towards: atEnd ? 0 : 1)
            return (path, cutT)
        }

        let end = head(atEnd: true)
        fills.append(end.path)
        var t0: CGFloat = 0
        let t1 = end.cutT
        switch g.style {
        case .doubleHeaded:
            let start = head(atEnd: false)
            fills.append(start.path)
            t0 = start.cutT
        case .lineWithDot:
            let r = max(w * 1.45, w / 2 + 1.5)
            fills.append(CGPath(ellipseIn: CGRect(x: p0.x - r, y: p0.y - r, width: 2 * r, height: 2 * r), transform: nil))
        case .straight, .curved, .tapered:
            break
        }

        if g.style == .tapered {
            fills.insert(taperedBody(p0, c, p2, upTo: t1, tailWidth: w * 0.45, headWidth: w * 2.1), at: 0)
            return ArrowPath(shaft: nil, shaftWidth: w, fills: fills, fillRounding: w * 0.2)
        }
        let shaft = CGMutablePath()
        if t1 > t0 {
            let (a, cc, b) = Geometry.quadSegment(p0, c, p2, t0, t1)
            shaft.move(to: a)
            shaft.addQuadCurve(to: b, control: cc)
        }
        return ArrowPath(shaft: shaft, shaftWidth: w, fills: fills, fillRounding: w * 0.2)
    }

    /// A filled body that widens from a rounded tail to the head.
    private static func taperedBody(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, upTo tEnd: CGFloat,
                                    tailWidth: CGFloat, headWidth: CGFloat) -> CGPath {
        let steps = 24
        var left: [CGPoint] = [], right: [CGPoint] = []
        for i in 0...steps {
            let t = tEnd * CGFloat(i) / CGFloat(steps)
            let p = Geometry.quad(p0, c, p2, t)
            let ahead = Geometry.quad(p0, c, p2, min(t + 0.01, 1))
            let behind = Geometry.quad(p0, c, p2, max(t - 0.01, 0))
            let n = Geometry.normal(Geometry.unit(from: behind, to: ahead))
            let f = CGFloat(i) / CGFloat(steps)
            // Ease the widening so the body reads as a pointer, not a wedge.
            let half = (tailWidth + (headWidth - tailWidth) * (f * (2 - f) * 0.6 + f * 0.4)) / 2
            left.append(Geometry.offset(p, n, half))
            right.append(Geometry.offset(p, n, -half))
        }
        let path = CGMutablePath()
        guard let firstLeft = left.first, let firstRight = right.first else { return path }
        path.move(to: firstLeft)
        for p in left.dropFirst() { path.addLine(to: p) }
        for p in right.reversed() { path.addLine(to: p) }
        // Round tail cap.
        let tailDir = Geometry.unit(from: Geometry.quad(p0, c, p2, 0.01), to: p0)
        path.addLine(to: firstRight)
        path.addQuadCurve(to: firstLeft, control: Geometry.offset(p0, tailDir, tailWidth))
        path.closeSubpath()
        return path
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
