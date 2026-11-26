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
        if let tail = c.tail, Geometry.distance(tail, c.center) > r * 1.15 {
            // Tangent lines from the tail tip to the circle, joined by the far arc.
            let d = Geometry.distance(tail, c.center)
            let theta = atan2(tail.y - c.center.y, tail.x - c.center.x)
            let alpha = acos(r / d)
            path.move(to: tail)
            path.addLine(to: CGPoint(x: c.center.x + r * cos(theta + alpha), y: c.center.y + r * sin(theta + alpha)))
            path.addArc(center: c.center, radius: r, startAngle: theta + alpha, endAngle: theta - alpha + 2 * .pi, clockwise: false)
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
