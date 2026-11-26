import AnnotationKit
import CoreGraphics
import Foundation

/// The remembered options of one tool, independent of image size.
/// Sizes are step indices; `ObjectStyle` pixel values are derived per document.
struct ToolSettings: Codable, Equatable, Sendable {
    var color: RGBAColor = .red
    var opacity: CGFloat = 1
    /// Index into `ObjectStyle.thicknessSteps` (0…4).
    var thicknessStep: Int = ObjectStyle.defaultThicknessStep
    /// Index into `ObjectStyle.textSizeSteps` (text) or `counterSizeSteps` (counter).
    var sizeStep: Int = ObjectStyle.defaultTextSizeStep
    var fill: ObjectStyle.FillMode = .outline
    var dash: ObjectStyle.Dash = .solid
    var contrastOutline = false
    var arrowStyle: ArrowStyle = .straight
    /// Rectangle corner radius in thickness units.
    var cornerRadiusUnits: CGFloat = 0
    var textStyle = TextStyle()
    var highlightRect = false
    var redactMode: RedactMode = .pixelate
    var counterNumbering: CounterGeometry.Numbering = .numeric
    var counterStart = 1

    /// Highlighter marks are much wider than strokes (6 × the thickness, as AnnotationKit's default).
    static let highlighterWidthFactor: CGFloat = 6

    /// Defaults per tool (first launch), from AnnotationKit's default styles.
    static func defaults(for kind: ToolKind) -> ToolSettings {
        var s = ToolSettings()
        switch kind {
        case .highlighter:
            s.color = .yellow
        case .redact:
            s.color = .black
        case .counter:
            s.sizeStep = ObjectStyle.defaultCounterSizeStep
        default:
            break
        }
        return s
    }

    // MARK: Pixel values for a document

    func lineWidth(for kind: ToolKind, pixelSize: CGSize) -> CGFloat {
        let width = ObjectStyle.lineWidth(step: thicknessStep, pixelSize: pixelSize)
        return kind == .highlighter ? width * Self.highlighterWidthFactor : width
    }

    func fontSize(for kind: ToolKind, pixelSize: CGSize, scale: CGFloat) -> CGFloat {
        kind == .counter
            ? ObjectStyle.counterRadius(step: sizeStep, pixelSize: pixelSize)
            : ObjectStyle.textFontSize(step: sizeStep, pixelSize: pixelSize, scale: scale)
    }

    func objectStyle(for kind: ToolKind, pixelSize: CGSize, scale: CGFloat) -> ObjectStyle {
        ObjectStyle(
            color: color,
            opacity: opacity,
            lineWidth: lineWidth(for: kind, pixelSize: pixelSize),
            fill: fill,
            dash: dash,
            fontSize: fontSize(for: kind, pixelSize: pixelSize, scale: scale),
            contrastOutline: contrastOutline
        )
    }

    /// Reads the settings back from an existing object (for the options bar).
    static func from(_ object: AnnotationObject, pixelSize: CGSize, scale: CGFloat, base: ToolSettings) -> ToolSettings {
        let kind = ToolKind.forShape(object.shape)
        var s = base
        let style = object.style
        s.color = style.color
        s.opacity = style.opacity
        s.fill = style.fill
        s.dash = style.dash
        s.contrastOutline = style.contrastOutline
        let widthFactor = kind == .highlighter ? highlighterWidthFactor : 1
        s.thicknessStep = ObjectStyle.thicknessStep(forLineWidth: style.lineWidth / widthFactor, pixelSize: pixelSize)
        let sizes: [CGFloat] = kind == .counter
            ? ObjectStyle.counterSizeSteps.indices.map { ObjectStyle.counterRadius(step: $0, pixelSize: pixelSize) }
            : ObjectStyle.textSizeSteps.indices.map { ObjectStyle.textFontSize(step: $0, pixelSize: pixelSize, scale: scale) }
        s.sizeStep = nearestIndex(style.fontSize, in: sizes)
        let unit = ObjectStyle.thicknessUnit(for: pixelSize)
        switch object.shape {
        case .arrow(let g): s.arrowStyle = g.style
        case .rectangle(_, let r): s.cornerRadiusUnits = r / max(unit, 0.0001)
        case .text(let box): s.textStyle = box.style
        case .highlight(let h):
            if case .rect = h { s.highlightRect = true } else { s.highlightRect = false }
        case .redact(_, let mode): s.redactMode = mode
        case .counter(let c): s.counterNumbering = c.numbering
        default: break
        }
        return s
    }

    static func nearestIndex(_ value: CGFloat, in table: [CGFloat]) -> Int {
        var best = 0
        for (i, v) in table.enumerated() where abs(v - value) < abs(table[best] - value) { best = i }
        return best
    }

    static func clamp(_ i: Int, _ count: Int) -> Int { min(max(i, 0), count - 1) }
}
