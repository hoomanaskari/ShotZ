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
