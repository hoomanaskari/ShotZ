import CoreGraphics

/// Per-tool default styles, scaled to the image (SPEC §5.3: a "medium" arrow looks the same
/// on a 1× capture and a 5K capture).
extension ObjectStyle {
    /// Index into `thicknessSteps` used for new objects.
    public static let defaultThicknessStep = 1

    /// Text sizes (in points at the capture's scale) offered by the options bar.
    public static let textSizeSteps: [CGFloat] = [12, 16, 20, 28, 40, 56]
    public static let defaultTextSizeStep = 2

    /// Counter sizes (badge radius as a multiple of `thicknessUnit`).
    public static let counterSizeSteps: [CGFloat] = [3.4, 4.5, 6, 8]
    public static let defaultCounterSizeStep = 1

    /// Stroke width in pixels for thickness step 0…4 on an image of `pixelSize`.
    public static func lineWidth(step: Int, pixelSize: CGSize) -> CGFloat {
        let i = min(max(step, 0), thicknessSteps.count - 1)
        return (thicknessUnit(for: pixelSize) * thicknessSteps[i] * 2).rounded() / 2
    }

    /// The nearest thickness step for an existing width (to reflect a selection in the options bar).
    public static func thicknessStep(forLineWidth width: CGFloat, pixelSize: CGSize) -> Int {
        let unit = thicknessUnit(for: pixelSize)
        return thicknessSteps.indices.min { abs(thicknessSteps[$0] * unit - width) < abs(thicknessSteps[$1] * unit - width) } ?? 1
    }

    /// Text font size in pixels: the step's point size times the capture's pixels-per-point,
    /// but never tiny on a huge image or huge on a tiny one.
    public static func textFontSize(step: Int, pixelSize: CGSize, scale: CGFloat) -> CGFloat {
        let i = min(max(step, 0), textSizeSteps.count - 1)
        let byScale = textSizeSteps[i] * max(scale, 1)
        let byImage = textSizeSteps[i] * thicknessUnit(for: pixelSize) / 2.4
        return max(byScale, byImage).rounded()
    }

    /// Counter badge radius in pixels (stored in `fontSize` for counters).
    public static func counterRadius(step: Int, pixelSize: CGSize) -> CGFloat {
        let i = min(max(step, 0), counterSizeSteps.count - 1)
        return max((thicknessUnit(for: pixelSize) * counterSizeSteps[i]).rounded(), 8)
    }

    /// The style a new object of `kind` gets on an image of this size, before the user changes anything.
    public static func defaultStyle(for kind: AnnotationKind, pixelSize: CGSize, scale: CGFloat = 1) -> ObjectStyle {
        let width = lineWidth(step: defaultThicknessStep, pixelSize: pixelSize)
        var style = ObjectStyle(
            color: .red, opacity: 1, lineWidth: width, fill: .outline, dash: .solid,
            fontSize: textFontSize(step: defaultTextSizeStep, pixelSize: pixelSize, scale: scale),
            contrastOutline: false
        )
        switch kind {
        case .arrow, .rectangle, .ellipse, .line, .pen, .text:
            break
        case .highlighter:
            style.color = .yellow
            style.lineWidth = (thicknessUnit(for: pixelSize) * 6).rounded()
        case .redact:
            style.color = .black
        case .counter:
            style.fontSize = counterRadius(step: defaultCounterSizeStep, pixelSize: pixelSize)
        }
        return style
    }
}
