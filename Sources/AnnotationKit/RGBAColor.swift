import CoreGraphics

/// An sRGB colour with alpha, components 0…1.
public struct RGBAColor: Codable, Sendable, Equatable, Hashable {
    public var red: CGFloat
    public var green: CGFloat
    public var blue: CGFloat
    public var alpha: CGFloat

    public init(red: CGFloat, green: CGFloat, blue: CGFloat, alpha: CGFloat = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    public var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

    public func withAlpha(_ alpha: CGFloat) -> RGBAColor {
        RGBAColor(red: red, green: green, blue: blue, alpha: alpha)
    }

    // The 8 presets (SPEC §5.3), Shotz's own values. Keys 1–8 map to `presets` in order.
    public static let red = RGBAColor(red: 0.93, green: 0.20, blue: 0.20)
    public static let orange = RGBAColor(red: 0.98, green: 0.55, blue: 0.10)
    public static let yellow = RGBAColor(red: 0.99, green: 0.83, blue: 0.10)
    public static let green = RGBAColor(red: 0.20, green: 0.72, blue: 0.33)
    public static let blue = RGBAColor(red: 0.15, green: 0.48, blue: 0.96)
    public static let purple = RGBAColor(red: 0.58, green: 0.32, blue: 0.90)
    public static let black = RGBAColor(red: 0.08, green: 0.08, blue: 0.09)
    public static let white = RGBAColor(red: 1, green: 1, blue: 1)

    public static let presets: [RGBAColor] = [.red, .orange, .yellow, .green, .blue, .purple, .black, .white]
}
