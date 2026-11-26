import CoreGraphics

public struct ArrowGeometry: Codable, Sendable, Equatable, Hashable {
    /// Tail.
    public var start: CGPoint
    /// Head.
    public var end: CGPoint
    /// Curve handle; used when `style == .curved`. This is the point the curve passes through
    /// at its middle (what the editor shows as the mid-point handle), not the raw Bézier
    /// control point; see `bezierControl`. nil = midpoint (a straight curve).
    public var control: CGPoint?
    public var style: ArrowStyle

    public init(start: CGPoint, end: CGPoint, control: CGPoint? = nil, style: ArrowStyle = .straight) {
        self.start = start
        self.end = end
        self.control = control
        self.style = style
    }

    /// Where the mid-point handle sits (the control, or the chord midpoint).
    public var handlePoint: CGPoint {
        control ?? CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
    }

    /// Quadratic Bézier control point such that the curve passes through `handlePoint` at t = 0.5.
    /// Non-curved styles return the chord midpoint (a straight spine).
    public var bezierControl: CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        guard style == .curved, let h = control else { return mid }
        return CGPoint(x: 2 * h.x - mid.x, y: 2 * h.y - mid.y)
    }

    /// Point on the arrow's spine at t ∈ 0…1.
    public func point(at t: CGFloat) -> CGPoint {
        Geometry.quad(start, bezierControl, end, t)
    }

    public var length: CGFloat { Geometry.distance(start, end) }
}

extension ArrowGeometry {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            start: try c.decode(CGPoint.self, forKey: .start),
            end: try c.decode(CGPoint.self, forKey: .end),
            control: try? c.decodeIfPresent(CGPoint.self, forKey: .control), // damaged control: straight curve
            style: (try? c.decodeIfPresent(ArrowStyle.self, forKey: .style)) ?? .straight
        )
    }
}
