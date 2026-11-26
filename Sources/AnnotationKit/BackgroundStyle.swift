import CoreGraphics

/// Presentation background around the image (SPEC §5.4). `nil` on the document = off.
public struct BackgroundStyle: Codable, Sendable, Equatable, Hashable {
    public enum Fill: Codable, Sendable, Equatable, Hashable {
        /// Transparent.
        case none
        case solid(RGBAColor)
        case gradient(GradientFill)
    }

    public struct GradientFill: Codable, Sendable, Equatable, Hashable {
        public var from: RGBAColor
        public var to: RGBAColor
        /// Degrees, 0 = left→right, 90 = top→bottom.
        public var angle: CGFloat

        public init(from: RGBAColor, to: RGBAColor, angle: CGFloat = 135) {
            self.from = from
            self.to = to
            self.angle = angle
        }
    }

    public enum Shadow: String, Codable, Sendable, CaseIterable { case off, soft, strong }

    public enum Alignment: String, Codable, Sendable, CaseIterable {
        case topLeft, top, topRight, left, center, right, bottomLeft, bottom, bottomRight
    }

    public enum Aspect: String, Codable, Sendable, CaseIterable {
        case auto
        case square = "1:1"
        case fourThree = "4:3"
        case sixteenNine = "16:9"
        case threeTwo = "3:2"

        /// width / height, nil for auto.
        public var ratio: CGFloat? {
            switch self {
            case .auto: nil
            case .square: 1
            case .fourThree: 4.0 / 3.0
            case .sixteenNine: 16.0 / 9.0
            case .threeTwo: 3.0 / 2.0
            }
        }
    }

    public var fill: Fill
    /// Fraction of the image's long edge, 0…0.25.
    public var padding: CGFloat
    public var autoBalance: Bool
    /// Inner corner radius of the image, base-image pixels.
    public var cornerRadius: CGFloat
    public var shadow: Shadow
    public var alignment: Alignment
    public var aspect: Aspect

    public init(
        fill: Fill = .solid(RGBAColor(red: 0.93, green: 0.94, blue: 0.96)),
        padding: CGFloat = 0.08,
        autoBalance: Bool = false,
        cornerRadius: CGFloat = 12,
        shadow: Shadow = .soft,
        alignment: Alignment = .center,
        aspect: Aspect = .auto
    ) {
        self.fill = fill
        self.padding = padding
        self.autoBalance = autoBalance
        self.cornerRadius = cornerRadius
        self.shadow = shadow
        self.alignment = alignment
        self.aspect = aspect
    }
}

extension BackgroundStyle {
    /// Tolerant decoding: missing or unknown values fall back to the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = BackgroundStyle()
        self.init(
            fill: (try? c.decodeIfPresent(Fill.self, forKey: .fill)) ?? d.fill,
            padding: (try? c.decodeIfPresent(CGFloat.self, forKey: .padding)) ?? d.padding,
            autoBalance: (try? c.decodeIfPresent(Bool.self, forKey: .autoBalance)) ?? d.autoBalance,
            cornerRadius: (try? c.decodeIfPresent(CGFloat.self, forKey: .cornerRadius)) ?? d.cornerRadius,
            shadow: (try? c.decodeIfPresent(Shadow.self, forKey: .shadow)) ?? d.shadow,
            alignment: (try? c.decodeIfPresent(Alignment.self, forKey: .alignment)) ?? d.alignment,
            aspect: (try? c.decodeIfPresent(Aspect.self, forKey: .aspect)) ?? d.aspect
        )
    }
}
