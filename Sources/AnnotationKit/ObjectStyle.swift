import CoreGraphics

/// Visual style shared by all object kinds. Shapes read the fields they need.
public struct ObjectStyle: Codable, Sendable, Equatable, Hashable {
    public enum FillMode: String, Codable, Sendable, CaseIterable {
        case outline
        case filled
        /// Outline plus a translucent fill of the same colour.
        case outlineTranslucentFill
    }

    public enum Dash: String, Codable, Sendable, CaseIterable { case solid, dashed }

    public var color: RGBAColor
    /// 0…1, applied on top of `color.alpha`.
    public var opacity: CGFloat
    /// Stroke width in base-image pixels.
    public var lineWidth: CGFloat
    public var fill: FillMode
    public var dash: Dash
    /// Text and counter size in base-image pixels.
    public var fontSize: CGFloat
    /// Subtle contrasting outline around strokes (arrows, SPEC §5.3).
    public var contrastOutline: Bool

    public init(
        color: RGBAColor = .red,
        opacity: CGFloat = 1,
        lineWidth: CGFloat = 4,
        fill: FillMode = .outline,
        dash: Dash = .solid,
        fontSize: CGFloat = 24,
        contrastOutline: Bool = false
    ) {
        self.color = color
        self.opacity = opacity
        self.lineWidth = lineWidth
        self.fill = fill
        self.dash = dash
        self.fontSize = fontSize
        self.contrastOutline = contrastOutline
    }

    public static let `default` = ObjectStyle()

    /// Thickness base unit for an image (SPEC §5.3: long edge / 400, clamped).
    public static func thicknessUnit(for pixelSize: CGSize) -> CGFloat {
        min(max(max(pixelSize.width, pixelSize.height) / 400, 1), 16)
    }

    /// The 5 thickness steps as multiples of `thicknessUnit`.
    public static let thicknessSteps: [CGFloat] = [0.5, 1, 1.5, 2.5, 4]
}

extension ObjectStyle {
    /// Tolerant decoding: missing or unknown values fall back to the defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = ObjectStyle.default
        self.init(
            color: (try? c.decodeIfPresent(RGBAColor.self, forKey: .color)) ?? d.color,
            opacity: (try? c.decodeIfPresent(CGFloat.self, forKey: .opacity)) ?? d.opacity,
            lineWidth: (try? c.decodeIfPresent(CGFloat.self, forKey: .lineWidth)) ?? d.lineWidth,
            fill: (try? c.decodeIfPresent(FillMode.self, forKey: .fill)) ?? d.fill,
            dash: (try? c.decodeIfPresent(Dash.self, forKey: .dash)) ?? d.dash,
            fontSize: (try? c.decodeIfPresent(CGFloat.self, forKey: .fontSize)) ?? d.fontSize,
            contrastOutline: (try? c.decodeIfPresent(Bool.self, forKey: .contrastOutline)) ?? d.contrastOutline
        )
    }
}
