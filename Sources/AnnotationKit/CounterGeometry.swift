import CoreGraphics

public struct CounterGeometry: Codable, Sendable, Equatable, Hashable {
    public enum Numbering: String, Codable, Sendable, CaseIterable {
        /// 1, 2, 3
        case numeric
        /// A, B, C
        case alphabetic
    }

    public var center: CGPoint
    /// Optional pointer tail end.
    public var tail: CGPoint?
    /// 1-based ordinal; rendered per `numbering`.
    public var value: Int
    public var numbering: Numbering

    public init(center: CGPoint, tail: CGPoint? = nil, value: Int, numbering: Numbering = .numeric) {
        self.center = center
        self.tail = tail
        self.value = value
        self.numbering = numbering
    }

    /// "3" or "C". Values past 26 continue as "AA", "AB", …
    public var label: String {
        switch numbering {
        case .numeric:
            return String(value)
        case .alphabetic:
            var n = max(value, 1)
            var s = ""
            while n > 0 {
                n -= 1
                s = String(UnicodeScalar(UInt8(65 + n % 26))) + s
                n /= 26
            }
            return s
        }
    }
}
