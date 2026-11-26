import CoreGraphics

/// Shotz's built-in background gradients (SPEC §5.4). Original colour pairs.
public struct GradientPreset: Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String
    public let fill: BackgroundStyle.GradientFill

    init(_ name: String, _ from: (CGFloat, CGFloat, CGFloat), _ to: (CGFloat, CGFloat, CGFloat), angle: CGFloat = 135) {
        self.name = name
        self.fill = BackgroundStyle.GradientFill(
            from: RGBAColor(red: from.0, green: from.1, blue: from.2),
            to: RGBAColor(red: to.0, green: to.1, blue: to.2), angle: angle)
    }

    public static let all: [GradientPreset] = [
        GradientPreset("Peach Fizz", (1.00, 0.80, 0.62), (0.96, 0.44, 0.54)),
        GradientPreset("Tidepool", (0.36, 0.86, 0.80), (0.18, 0.42, 0.82)),
        GradientPreset("Lilac Hour", (0.80, 0.70, 0.98), (0.45, 0.36, 0.86)),
        GradientPreset("Citrus Grove", (0.98, 0.92, 0.45), (0.42, 0.80, 0.42)),
        GradientPreset("Ember", (1.00, 0.66, 0.28), (0.82, 0.18, 0.30)),
        GradientPreset("Glacier", (0.90, 0.96, 1.00), (0.56, 0.72, 0.92), angle: 90),
        GradientPreset("Moss & Stone", (0.70, 0.78, 0.62), (0.36, 0.44, 0.40)),
        GradientPreset("Midnight Ink", (0.20, 0.24, 0.42), (0.06, 0.07, 0.14), angle: 90),
        GradientPreset("Rose Quartz", (1.00, 0.86, 0.90), (0.86, 0.62, 0.80)),
        GradientPreset("Sea Glass", (0.80, 0.96, 0.90), (0.46, 0.76, 0.84), angle: 45),
        GradientPreset("Sandbar", (0.98, 0.92, 0.82), (0.84, 0.70, 0.56)),
        GradientPreset("Graphite", (0.52, 0.54, 0.58), (0.20, 0.21, 0.24), angle: 90),
    ]
}
