import CoreGraphics

public struct RedactMode: Codable, Sendable, Equatable, Hashable {
    public enum Kind: String, Codable, Sendable, CaseIterable {
        case pixelate
        case blur
        /// Opaque fill in `ObjectStyle.color`.
        case solid
    }

    public var kind: Kind
    /// 0…1; the default is strong enough that text is unrecoverable.
    public var strength: CGFloat

    public init(kind: Kind, strength: CGFloat = 0.6) {
        self.kind = kind
        self.strength = strength
    }

    public static let pixelate = RedactMode(kind: .pixelate)
    public static let blur = RedactMode(kind: .blur)
    public static let solid = RedactMode(kind: .solid, strength: 1)
}
