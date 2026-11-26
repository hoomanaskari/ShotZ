import CoreGraphics

/// A selection handle in base-image pixel space.
public struct Handle: Sendable, Equatable, Hashable {
    public enum Kind: String, Sendable, CaseIterable {
        // Box shapes (8)
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        // Lines and arrows
        case start, end, control
        // Counter pointer
        case tail
    }

    public var kind: Kind
    public var position: CGPoint

    public init(kind: Kind, position: CGPoint) {
        self.kind = kind
        self.position = position
    }
}
