import CoreGraphics

public struct ArrowGeometry: Codable, Sendable, Equatable, Hashable {
    /// Tail.
    public var start: CGPoint
    /// Head.
    public var end: CGPoint
    /// Curve control point (mid-point handle); used when `style == .curved`.
    public var control: CGPoint?
    public var style: ArrowStyle

    public init(start: CGPoint, end: CGPoint, control: CGPoint? = nil, style: ArrowStyle = .straight) {
        self.start = start
        self.end = end
        self.control = control
        self.style = style
    }
}
