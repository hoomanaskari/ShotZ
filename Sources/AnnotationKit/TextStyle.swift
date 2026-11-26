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

extension TextStyle {
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            decoration: (try? c.decodeIfPresent(Decoration.self, forKey: .decoration)) ?? .plain,
            isBold: (try? c.decodeIfPresent(Bool.self, forKey: .isBold)) ?? false,
            alignment: (try? c.decodeIfPresent(Alignment.self, forKey: .alignment)) ?? .left
        )
    }
}
