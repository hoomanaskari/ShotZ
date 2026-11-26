public enum ArrowStyle: String, Codable, Sendable, CaseIterable {
    case straight
    /// Uses `ArrowGeometry.control` as a quadratic control point.
    case curved
    /// Tapered body widening to the head ("pointer").
    case tapered
    case doubleHeaded
    /// A line with a dot at the start and a head at the end.
    case lineWithDot

    /// Next style when the arrow tool key is pressed again.
    public var next: ArrowStyle {
        let all = Self.allCases
        let i = all.firstIndex(of: self) ?? 0
        return all[(i + 1) % all.count]
    }
}
