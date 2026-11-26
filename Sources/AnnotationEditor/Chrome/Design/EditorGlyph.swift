import AnnotationKit
import AppKit
import ShotzCore

/// Every icon the editor chrome shows. One place maps them to artwork, so the
/// whole set can move to ShotzCore's shared `ShotzIcon` set in one change.
enum EditorGlyph: Hashable, Sendable {
    // Tools
    case select, arrow, rectangle, ellipse, line, text, highlighter, redact, counter, pen, crop, background
    // Actions
    case copy, save, drag, more, eyedropper
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

/// Chrome icons from ShotzCore's shared `ShotzIcon` set (Phosphor regular plus ShotZ
/// custom glyphs). The few the set does not have yet are drawn here in the same weight
/// (marked below) until they are added to it.
@MainActor enum EditorGlyphs {
    private static var cache: [String: NSImage] = [:]

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
        // Not in the shared set yet (requested): drawn below.
        case .eyedropper, .strength, .angle: nil
        }
    }

    /// 18 pt in the tool strip, 16 pt in the options bar and menus (the set's guidance).
    static func image(_ glyph: EditorGlyph, size: CGFloat = 16, label: String? = nil) -> NSImage {
        if let icon = shotzIcon(glyph) {
            let image = icon.image(pointSize: size)
            return withLabel(image, label)
        }
        let key = "\(glyph)-\(size)"
        if let cached = cache[key] { return withLabel(cached, label) }
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            ctx.scaleBy(x: rect.width / 20, y: rect.height / 20)
            NSColor.black.setStroke()
            NSColor.black.setFill()
            draw(glyph, in: ctx)
            return true
        }
        image.isTemplate = true
        cache[key] = image
        return withLabel(image, label)
    }

    private static func withLabel(_ image: NSImage, _ label: String?) -> NSImage {
        guard let label else { return image }
        let copy = (image.copy() as? NSImage) ?? image
        copy.accessibilityDescription = label
        return copy
    }

    // MARK: Drawing (20 × 20, top-left origin)

    private static let weight: CGFloat = 1.6

    private static func stroke(_ ctx: CGContext, _ path: CGPath, width: CGFloat = weight, dash: [CGFloat] = []) {
        ctx.saveGState()
        ctx.setLineWidth(width)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        if !dash.isEmpty { ctx.setLineDash(phase: 0, lengths: dash) }
        ctx.addPath(path)
        ctx.strokePath()
        ctx.restoreGState()
    }

    private static func fill(_ ctx: CGContext, _ path: CGPath, alpha: CGFloat = 1) {
        ctx.saveGState()
        ctx.setAlpha(alpha)
        ctx.addPath(path)
        ctx.fillPath()
        ctx.restoreGState()
    }

    private static func line(_ a: CGPoint, _ b: CGPoint) -> CGPath {
        let p = CGMutablePath(); p.move(to: a); p.addLine(to: b); return p
    }

    private static func head(at tip: CGPoint, from tail: CGPoint, length: CGFloat = 6, spread: CGFloat = 0.46) -> CGPath {
        let a = atan2(tip.y - tail.y, tip.x - tail.x)
        let p = CGMutablePath()
        p.move(to: tip)
        p.addLine(to: CGPoint(x: tip.x - length * cos(a - spread), y: tip.y - length * sin(a - spread)))
        p.addLine(to: CGPoint(x: tip.x - length * cos(a + spread), y: tip.y - length * sin(a + spread)))
        p.closeSubpath()
        return p
    }

    private static func letter(_ ctx: CGContext, _ s: String, size: CGFloat, weight w: NSFont.Weight, center: CGPoint, outlined: Bool = false, knockout: Bool = false) {
        let font = NSFont.systemFont(ofSize: size, weight: w)
        var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        if outlined { attrs[.strokeWidth] = 4; attrs[.strokeColor] = NSColor.black }
        let str = NSAttributedString(string: s, attributes: attrs)
        let sz = str.size()
        if knockout { ctx.setBlendMode(.destinationOut) }
        str.draw(at: CGPoint(x: center.x - sz.width / 2, y: center.y - sz.height / 2))
        ctx.setBlendMode(.normal)
    }

    /// Fallback artwork for the icons the shared set does not have yet.
    private static func draw(_ glyph: EditorGlyph, in ctx: CGContext) {
        switch glyph {
        case .eyedropper:
            let body = CGMutablePath()
            body.move(to: CGPoint(x: 11.5, y: 5.5)); body.addLine(to: CGPoint(x: 4, y: 13)); body.addLine(to: CGPoint(x: 3.5, y: 16.5))
            body.addLine(to: CGPoint(x: 7, y: 16)); body.addLine(to: CGPoint(x: 14.5, y: 8.5))
            stroke(ctx, body)
            // The bulb: a rounded capsule across the top-right, at 45°.
            ctx.saveGState()
            ctx.translateBy(x: 14.8, y: 5.2)
            ctx.rotate(by: .pi / 4)
            fill(ctx, CGPath(roundedRect: CGRect(x: -3.6, y: -2.3, width: 7.2, height: 4.6), cornerWidth: 2.3, cornerHeight: 2.3, transform: nil))
            ctx.restoreGState()
            stroke(ctx, line(CGPoint(x: 10, y: 4), CGPoint(x: 16, y: 10)))
        case .strength:
            let p = CGMutablePath()
            p.addArc(center: CGPoint(x: 10, y: 12), radius: 7, startAngle: .pi * 0.9, endAngle: .pi * 2.1, clockwise: false)
            stroke(ctx, p)
            stroke(ctx, line(CGPoint(x: 10, y: 12), CGPoint(x: 14, y: 7.5)))
        case .angle:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 4, y: 16)); p.addLine(to: CGPoint(x: 17, y: 16))
            stroke(ctx, p)
            let arc = CGMutablePath()
            arc.addArc(center: CGPoint(x: 4, y: 16), radius: 6.5, startAngle: -.pi / 4, endAngle: 0, clockwise: false)
            stroke(ctx, arc, width: 1.2)
        default:
            break
        }
    }
}
