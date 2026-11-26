import AnnotationKit
import CoreGraphics
import Foundation

/// The remembered options of one tool, independent of image size.
/// Sizes are step indices; `ObjectStyle` pixel values are derived per document.
struct ToolSettings: Codable, Equatable, Sendable {
    var color: RGBAColor = .red
    var opacity: CGFloat = 1
    /// Index into `ToolSettings.thicknessMultipliers`.
    var thicknessStep: Int = 2
    /// Index into `textSizeMultipliers` / `counterSizeMultipliers`.
    var sizeStep: Int = 1
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

    static let thicknessMultipliers = ObjectStyle.thicknessSteps
    static let textSizeMultipliers: [CGFloat] = [3, 4.5, 6, 8, 11]
    static let counterSizeMultipliers: [CGFloat] = [2.5, 3.5, 5]
    /// Highlighter marks are much wider than strokes.
    static let highlighterWidthFactor: CGFloat = 5

    /// Defaults per tool (first launch).
    static func defaults(for kind: ToolKind) -> ToolSettings {
        var s = ToolSettings()
        switch kind {
        case .highlighter:
            s.color = .yellow
            s.thicknessStep = 2
        case .pen:
            s.thicknessStep = 1
        case .text:
            s.sizeStep = 1
        case .redact:
            s.color = .black
        case .rectangle:
            s.cornerRadiusUnits = 0
        default:
            break
        }
        return s
    }

    // MARK: Pixel values for a document

    func lineWidth(for kind: ToolKind, unit: CGFloat) -> CGFloat {
        let step = Self.thicknessMultipliers[Self.clamp(thicknessStep, Self.thicknessMultipliers.count)]
        return unit * step * (kind == .highlighter ? Self.highlighterWidthFactor : 1)
    }

    func fontSize(for kind: ToolKind, unit: CGFloat) -> CGFloat {
        let table = kind == .counter ? Self.counterSizeMultipliers : Self.textSizeMultipliers
        return unit * table[Self.clamp(sizeStep, table.count)]
    }

    func objectStyle(for kind: ToolKind, unit: CGFloat) -> ObjectStyle {
        ObjectStyle(
            color: color,
            opacity: opacity,
            lineWidth: lineWidth(for: kind, unit: unit),
            fill: fill,
            dash: dash,
            fontSize: fontSize(for: kind, unit: unit),
            contrastOutline: contrastOutline
        )
    }

    /// Reads the settings back from an existing object (for the options bar).
    static func from(_ object: AnnotationObject, unit: CGFloat, base: ToolSettings) -> ToolSettings {
        let kind = ToolKind.forShape(object.shape)
        var s = base
        let style = object.style
        s.color = style.color
        s.opacity = style.opacity
        s.fill = style.fill
        s.dash = style.dash
        s.contrastOutline = style.contrastOutline
        let widthFactor = kind == .highlighter ? highlighterWidthFactor : 1
        s.thicknessStep = nearestIndex(style.lineWidth / max(unit * widthFactor, 0.0001), in: thicknessMultipliers)
        let sizeTable = kind == .counter ? counterSizeMultipliers : textSizeMultipliers
        s.sizeStep = nearestIndex(style.fontSize / max(unit, 0.0001), in: sizeTable)
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
