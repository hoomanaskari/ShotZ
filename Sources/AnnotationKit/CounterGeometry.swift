import CoreGraphics

public struct CounterGeometry: Codable, Sendable, Equatable, Hashable {
    public enum Numbering: String, Codable, Sendable, CaseIterable {
        /// 1, 2, 3
        case numeric
        /// A, B, C
        case alphabetic
    }

    /// The badge radius comes from `ObjectStyle.fontSize` (pixels); colour from `ObjectStyle.color`.
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

extension CounterGeometry {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            center: try c.decode(CGPoint.self, forKey: .center),
            tail: try? c.decodeIfPresent(CGPoint.self, forKey: .tail), // damaged tail: drop it
            value: (try? c.decodeIfPresent(Int.self, forKey: .value)) ?? 1,
            numbering: (try? c.decodeIfPresent(Numbering.self, forKey: .numbering)) ?? .numeric
        )
    }
}
