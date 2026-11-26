import CoreGraphics

/// The badge outline of a counter: a circle, or a tear-drop when it has a pointer tail.
/// For counters `ObjectStyle.fontSize` is the badge radius in pixels.
struct CounterShape {
    let center: CGPoint
    let radius: CGFloat
    let path: CGPath

    init(_ c: CounterGeometry, radius rawRadius: CGFloat) {
        let r = max(rawRadius, 2)
        center = c.center
        radius = r
        let path = CGMutablePath()
        if let tail = c.tail, Geometry.distance(tail, c.center) > r * 1.3 {
            // A slim pointer that grows out of the badge: it leaves the circle ±30° either side
            // of the tail direction and narrows along concave curves to the tip, so the
            // outline (and its white rim) reads as one continuous shape.
            let theta = atan2(tail.y - c.center.y, tail.x - c.center.x)
            let beta = CGFloat.pi / 6
            let u = CGVector(dx: cos(theta), dy: sin(theta))
            let n = Geometry.normal(u)
            let a = CGPoint(x: c.center.x + r * cos(theta + beta), y: c.center.y + r * sin(theta + beta))
            let reach = Geometry.distance(tail, c.center) - r
            let waist = Geometry.offset(c.center, u, r + reach * 0.3)
            path.move(to: tail)
            path.addQuadCurve(to: a, control: Geometry.offset(waist, n, r * 0.2))
            path.addArc(center: c.center, radius: r, startAngle: theta + beta, endAngle: theta - beta + 2 * .pi, clockwise: false)
            path.addQuadCurve(to: tail, control: Geometry.offset(waist, n, -r * 0.2))
            path.closeSubpath()
        } else {
            path.addEllipse(in: CGRect(x: c.center.x - r, y: c.center.y - r, width: 2 * r, height: 2 * r))
        }
        self.path = path
    }

    var ringWidth: CGFloat { max(radius * 0.12, 1) }

    var shadowOffset: CGSize { CGSize(width: 0, height: radius * 0.08) }
    var shadowBlur: CGFloat { radius * 0.3 }

    var bounds: CGRect {
        let base = path.boundingBoxOfPath.insetBy(dx: -ringWidth, dy: -ringWidth)
        let shadow = base.offsetBy(dx: shadowOffset.width, dy: shadowOffset.height).insetBy(dx: -shadowBlur, dy: -shadowBlur)
        return base.union(shadow)
    }
}
