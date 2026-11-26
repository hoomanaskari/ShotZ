import AnnotationKit
import ShotzCore

/// Every icon the editor chrome shows. One place maps them to artwork, so the
/// whole set can move to ShotzCore's shared `ShotzIcon` set in one change.
enum EditorGlyph: Hashable, Sendable {
    // Tools
    case select, arrow, rectangle, ellipse, line, text, highlighter, redact, counter, pen, crop, background
    // Actions
    case copy, save, drag, more, eyedropper, zoomIn, zoomOut
    // Option pickers
    case arrowStyle(ArrowStyle)
    case fill(ObjectStyle.FillMode, ellipse: Bool)
    case dash(ObjectStyle.Dash)
    case textDecoration(TextStyle.Decoration)
    case textAlign(TextStyle.Alignment)
    case bold
    case highlightFreehand, highlightRect
    case redactMode(RedactMode.Kind)
    case thickness(Int)
    case opacity, cornerRadius, strength, angle, padding

    static func tool(_ kind: ToolKind) -> EditorGlyph {
        switch kind {
        case .select: .select
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .text: .text
        case .highlighter: .highlighter
        case .redact: .redact
        case .counter: .counter
        case .pen: .pen
        case .crop: .crop
        }
    }
}

/// Chrome icons come only from ShotzCore's shared `ShotzIcon` set (Phosphor regular plus
/// ShotZ custom glyphs); the editor draws none of its own.
enum EditorGlyphs {
    /// The shared icon for a glyph, or nil while the set lacks it.
    static func shotzIcon(_ glyph: EditorGlyph) -> ShotzIcon? {
        switch glyph {
        case .select: .select
        case .arrow: .arrowTool
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .text: .text
        case .highlighter: .highlighter
        case .redact: .redact
        case .counter: .counter
        case .pen: .pen
        case .crop: .crop
        case .background: .background
        case .copy: .copy
        case .save: .save
        case .drag: .dragHandle
        case .more: .more
        case .zoomIn: .zoomIn
        case .zoomOut: .zoomOut
        case .arrowStyle(let a):
            switch a {
            case .straight: .arrowStraight
            case .curved: .arrowCurved
            case .tapered: .arrowTapered
            case .doubleHeaded: .arrowDoubleHeaded
            case .lineWithDot: .arrowLineWithDot
            }
        case .fill(let mode, _):
            // The set's fill glyphs are box-shaped; they read for ellipses too.
            switch mode {
            case .outline: .fillOutline
            case .filled: .fillSolid
            case .outlineTranslucentFill: .fillOutlineTranslucent
            }
        case .dash(let d): d == .solid ? .lineSolid : .lineDashed
        case .textDecoration(let d):
            switch d {
            case .plain: .textPlain
            case .outlined: .textOutlined
            case .solidPill: .textSolidPill
            case .translucentPill: .textTranslucentPill
            }
        case .textAlign(let a):
            switch a {
            case .left: .alignLeft
            case .center: .alignCenter
            case .right: .alignRight
            }
        case .bold: .bold
        case .highlightFreehand: .highlightFreehand
        case .highlightRect: .highlightRect
        case .redactMode(let k):
            switch k {
            case .pixelate: .redactPixelate
            case .blur: .redactBlur
            case .solid: .redactSolid
            }
        case .thickness(let step): ShotzIcon.thicknessSteps[min(max(step, 0), ShotzIcon.thicknessSteps.count - 1)]
        case .opacity: .opacity
        case .cornerRadius: .cornerRadius
        case .padding: .padding
        case .eyedropper: .eyedropper
        case .strength: .strength
        case .angle: .angle
        }
    }
}
