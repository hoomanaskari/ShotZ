import CoreGraphics

/// Small internal vector and curve helpers shared by the renderer, hit testing and transforms.
enum Geometry {
    static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(b.x - a.x, b.y - a.y) }

    static func lerp(_ a: CGPoint, _ b: CGPoint, _ t: CGFloat) -> CGPoint {
        CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t)
    }

    static func midpoint(_ a: CGPoint, _ b: CGPoint) -> CGPoint { lerp(a, b, 0.5) }

    static func unit(from a: CGPoint, to b: CGPoint) -> CGVector {
        let d = distance(a, b)
        guard d > 1e-9 else { return CGVector(dx: 1, dy: 0) }
        return CGVector(dx: (b.x - a.x) / d, dy: (b.y - a.y) / d)
    }

    static func offset(_ p: CGPoint, _ v: CGVector, _ k: CGFloat) -> CGPoint {
        CGPoint(x: p.x + v.dx * k, y: p.y + v.dy * k)
    }

    /// Left-hand normal of a unit vector.
    static func normal(_ v: CGVector) -> CGVector { CGVector(dx: -v.dy, dy: v.dx) }

    /// Point on the quadratic Bézier (p0, c, p2) at t.
    static func quad(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return CGPoint(
            x: u * u * p0.x + 2 * u * t * c.x + t * t * p2.x,
            y: u * u * p0.y + 2 * u * t * c.y + t * t * p2.y
        )
    }

    /// The part of quadratic (p0, c, p2) between t0 and t1, as (start, control, end).
    static func quadSegment(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, _ t0: CGFloat, _ t1: CGFloat)
        -> (CGPoint, CGPoint, CGPoint) {
        let a = quad(p0, c, p2, t0)
        let b = quad(p0, c, p2, t1)
        // Control of the sub-curve = intersection of the tangents at t0 and t1, which for a
        // quadratic is the de Casteljau blend evaluated at (t0, t1).
        let c0 = lerp(lerp(p0, c, t0), lerp(c, p2, t0), t1)
        return (a, c0, b)
    }

    /// Parameter t on the quadratic whose point lies `length` (straight-line) away from the
    /// point at `fromT`, searching towards `towardsT`. Used to cut shafts under arrow heads.
    static func quadParameter(_ p0: CGPoint, _ c: CGPoint, _ p2: CGPoint, distance length: CGFloat,
                              from fromT: CGFloat, towards towardsT: CGFloat) -> CGFloat {
        let anchor = quad(p0, c, p2, fromT)
        var lo = fromT, hi = towardsT
        if distance(anchor, quad(p0, c, p2, hi)) < length { return hi }
        for _ in 0..<30 {
            let mid = (lo + hi) / 2
            if distance(anchor, quad(p0, c, p2, mid)) < length { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    static func distanceToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
        let dx = b.x - a.x, dy = b.y - a.y
        let len2 = dx * dx + dy * dy
        guard len2 > 1e-12 else { return distance(p, a) }
        let t = max(0, min(1, ((p.x - a.x) * dx + (p.y - a.y) * dy) / len2))
        return distance(p, CGPoint(x: a.x + t * dx, y: a.y + t * dy))
    }

    static func rectContaining(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    static func rect(_ a: CGPoint, _ b: CGPoint) -> CGRect { rectContaining([a, b]) }
}

extension RGBAColor {
    /// Relative luminance (sRGB, approximate gamma), 0…1.
    var luminance: CGFloat {
        func lin(_ c: CGFloat) -> CGFloat { c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(red) + 0.7152 * lin(green) + 0.0722 * lin(blue)
    }

    /// Black or white, whichever reads better on top of this colour.
    public var contrastingTextColor: RGBAColor {
        luminance > 0.36 ? RGBAColor(red: 0.07, green: 0.07, blue: 0.08) : .white
    }

    func scaledAlpha(_ k: CGFloat) -> RGBAColor { withAlpha(alpha * k) }
}

extension CGContext {
    /// Sets a shadow given in top-left pixel space (y down), converting to the context's
    /// base space, which Core Graphics uses for shadow offsets and blur regardless of the CTM.
    func setShadowInUserSpace(offset: CGSize, blur: CGFloat, color: CGColor) {
        let t = ctm
        let d = offset.applying(t)
        let scale = sqrt(abs(t.a * t.d - t.b * t.c))
        setShadow(offset: d, blur: blur * scale, color: color)
    }

    /// Draws `image` into `rect` given in a top-left (flipped) user space.
    func drawFlipped(_ image: CGImage, in rect: CGRect) {
        saveGState()
        translateBy(x: rect.minX, y: rect.maxY)
        scaleBy(x: 1, y: -1)
        draw(image, in: CGRect(origin: .zero, size: rect.size))
        restoreGState()
    }
}
