public struct TextStyle: Codable, Sendable, Equatable, Hashable {
    public enum Decoration: String, Codable, Sendable, CaseIterable {
        case plain
        case outlined
        case solidPill
        case translucentPill
    }

    public enum Alignment: String, Codable, Sendable, CaseIterable { case left, center, right }

    public var decoration: Decoration
    public var isBold: Bool
    public var alignment: Alignment

    public init(decoration: Decoration = .plain, isBold: Bool = false, alignment: Alignment = .left) {
        self.decoration = decoration
        self.isBold = isBold
        self.alignment = alignment
    }
}
