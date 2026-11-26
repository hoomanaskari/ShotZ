import AnnotationKit
import AppKit

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

// TEMP until ShotzCore's `ShotzIcon` set lands (engineer C): Shotz's own placeholder
// artwork, drawn as template images on a 20-pt grid with one 1.6-pt stroke weight
// so every glyph reads as one family.
@MainActor enum EditorGlyphs {
    private static var cache: [String: NSImage] = [:]

    static func image(_ glyph: EditorGlyph, size: CGFloat = 18, label: String? = nil) -> NSImage {
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

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func draw(_ glyph: EditorGlyph, in ctx: CGContext) {
        switch glyph {
        case .select:
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: 5, y: 2.5), CGPoint(x: 5, y: 16.5), CGPoint(x: 8.6, y: 13.2),
                                 CGPoint(x: 11.2, y: 18.2), CGPoint(x: 13.4, y: 17.2), CGPoint(x: 10.9, y: 12.3), CGPoint(x: 15.5, y: 12.3)])
            p.closeSubpath()
            fill(ctx, p)
        case .arrow, .arrowStyle(.straight):
            stroke(ctx, line(CGPoint(x: 3.5, y: 16.5), CGPoint(x: 14.5, y: 5.5)))
            fill(ctx, head(at: CGPoint(x: 16.5, y: 3.5), from: CGPoint(x: 3.5, y: 16.5), length: 7))
        case .arrowStyle(.curved):
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 3.5, y: 16.5))
            p.addQuadCurve(to: CGPoint(x: 14.5, y: 5.5), control: CGPoint(x: 4, y: 5))
            stroke(ctx, p)
            fill(ctx, head(at: CGPoint(x: 17, y: 5.5), from: CGPoint(x: 9, y: 5.2), length: 6.5))
        case .arrowStyle(.tapered):
            let p = CGMutablePath()
            p.addLines(between: [CGPoint(x: 3, y: 17), CGPoint(x: 12.2, y: 6.2), CGPoint(x: 10, y: 4.6),
                                 CGPoint(x: 17, y: 3), CGPoint(x: 15.4, y: 10), CGPoint(x: 13.8, y: 7.8), CGPoint(x: 3.6, y: 17.6)])
            p.closeSubpath()
            fill(ctx, p)
        case .arrowStyle(.doubleHeaded):
            stroke(ctx, line(CGPoint(x: 5.5, y: 14.5), CGPoint(x: 14.5, y: 5.5)))
            fill(ctx, head(at: CGPoint(x: 16.8, y: 3.2), from: CGPoint(x: 3.2, y: 16.8), length: 6.5))
            fill(ctx, head(at: CGPoint(x: 3.2, y: 16.8), from: CGPoint(x: 16.8, y: 3.2), length: 6.5))
        case .arrowStyle(.lineWithDot):
            stroke(ctx, line(CGPoint(x: 5, y: 15), CGPoint(x: 14.5, y: 5.5)))
            fill(ctx, CGPath(ellipseIn: CGRect(x: 2, y: 13, width: 5, height: 5), transform: nil))
            fill(ctx, head(at: CGPoint(x: 16.8, y: 3.2), from: CGPoint(x: 3.2, y: 16.8), length: 6.5))
        case .rectangle:
            stroke(ctx, CGPath(roundedRect: CGRect(x: 3, y: 5, width: 14, height: 10.5), cornerWidth: 2, cornerHeight: 2, transform: nil))
        case .ellipse:
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 2.8, y: 4.2, width: 14.4, height: 11.6), transform: nil))
        case .line:
            stroke(ctx, line(CGPoint(x: 4, y: 16), CGPoint(x: 16, y: 4)))
        case .pen:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 3, y: 13.5))
            p.addCurve(to: CGPoint(x: 10, y: 10), control1: CGPoint(x: 5, y: 4), control2: CGPoint(x: 9, y: 4.5))
            p.addCurve(to: CGPoint(x: 17, y: 6.5), control1: CGPoint(x: 11, y: 16.5), control2: CGPoint(x: 15, y: 16))
            stroke(ctx, p)
        case .highlighter:
            let body = CGMutablePath()
            body.addLines(between: [CGPoint(x: 9.5, y: 11.5), CGPoint(x: 14.8, y: 2.6), CGPoint(x: 17.6, y: 4.2),
                                    CGPoint(x: 12.4, y: 13.1)])
            body.closeSubpath()
            stroke(ctx, body)
            let tip = CGMutablePath()
            tip.addLines(between: [CGPoint(x: 9.5, y: 11.5), CGPoint(x: 12.4, y: 13.1), CGPoint(x: 10.4, y: 15.4), CGPoint(x: 8.6, y: 14.4)])
            tip.closeSubpath()
            fill(ctx, tip)
            fill(ctx, CGPath(roundedRect: CGRect(x: 2.5, y: 16.2, width: 15, height: 2.3), cornerWidth: 1.1, cornerHeight: 1.1, transform: nil), alpha: 0.45)
        case .text:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 4, y: 6)); p.addLine(to: CGPoint(x: 4, y: 4)); p.addLine(to: CGPoint(x: 16, y: 4)); p.addLine(to: CGPoint(x: 16, y: 6))
            p.move(to: CGPoint(x: 10, y: 4)); p.addLine(to: CGPoint(x: 10, y: 16.5))
            p.move(to: CGPoint(x: 7.5, y: 16.5)); p.addLine(to: CGPoint(x: 12.5, y: 16.5))
            stroke(ctx, p)
        case .counter:
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 2.8, y: 2.8, width: 14.4, height: 14.4), transform: nil))
            letter(ctx, "1", size: 9.5, weight: .bold, center: CGPoint(x: 10, y: 10.2))
        case .redact, .redactMode(.pixelate):
            let cells: [(Int, Int, CGFloat)] = [(0, 0, 1), (1, 0, 0.45), (2, 0, 0.8), (0, 1, 0.55), (1, 1, 1), (2, 1, 0.35),
                                                (0, 2, 0.85), (1, 2, 0.4), (2, 2, 1)]
            for (x, y, a) in cells {
                fill(ctx, CGPath(roundedRect: CGRect(x: 3 + CGFloat(x) * 4.9, y: 3 + CGFloat(y) * 4.9, width: 4.3, height: 4.3),
                                 cornerWidth: 0.8, cornerHeight: 0.8, transform: nil), alpha: a)
            }
        case .redactMode(.blur):
            for (i, a) in [(0, 0.22), (1, 0.4), (2, 0.65), (3, 1.0)] as [(Int, CGFloat)] {
                let inset = CGFloat(i) * 1.9
                fill(ctx, CGPath(ellipseIn: CGRect(x: 2.5 + inset, y: 2.5 + inset, width: 15 - 2 * inset, height: 15 - 2 * inset), transform: nil), alpha: a * 0.6)
            }
        case .redactMode(.solid):
            fill(ctx, CGPath(roundedRect: CGRect(x: 3, y: 5, width: 14, height: 10), cornerWidth: 2, cornerHeight: 2, transform: nil))
        case .crop:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 6, y: 2.5)); p.addLine(to: CGPoint(x: 6, y: 14)); p.addLine(to: CGPoint(x: 17.5, y: 14))
            p.move(to: CGPoint(x: 2.5, y: 6)); p.addLine(to: CGPoint(x: 14, y: 6)); p.addLine(to: CGPoint(x: 14, y: 17.5))
            stroke(ctx, p)
        case .background:
            stroke(ctx, CGPath(roundedRect: CGRect(x: 2.5, y: 3.5, width: 15, height: 13), cornerWidth: 3, cornerHeight: 3, transform: nil))
            fill(ctx, CGPath(roundedRect: CGRect(x: 6, y: 6.8, width: 8, height: 6.4), cornerWidth: 1.4, cornerHeight: 1.4, transform: nil))
        case .copy:
            stroke(ctx, CGPath(roundedRect: CGRect(x: 6.5, y: 6.5, width: 10, height: 11), cornerWidth: 2, cornerHeight: 2, transform: nil))
            let back = CGMutablePath()
            back.move(to: CGPoint(x: 13.5, y: 4)); back.addLine(to: CGPoint(x: 13.5, y: 3.5))
            back.addArc(tangent1End: CGPoint(x: 13.5, y: 2.5), tangent2End: CGPoint(x: 11, y: 2.5), radius: 1.5)
            back.addLine(to: CGPoint(x: 5, y: 2.5))
            back.addArc(tangent1End: CGPoint(x: 3.5, y: 2.5), tangent2End: CGPoint(x: 3.5, y: 5), radius: 1.5)
            back.addLine(to: CGPoint(x: 3.5, y: 13)); back.addLine(to: CGPoint(x: 4, y: 13))
            stroke(ctx, back)
        case .save:
            let tray = CGMutablePath()
            tray.move(to: CGPoint(x: 3, y: 12)); tray.addLine(to: CGPoint(x: 3, y: 16.5)); tray.addLine(to: CGPoint(x: 17, y: 16.5)); tray.addLine(to: CGPoint(x: 17, y: 12))
            stroke(ctx, tray)
            stroke(ctx, line(CGPoint(x: 10, y: 2.5), CGPoint(x: 10, y: 12)))
            let chevron = CGMutablePath()
            chevron.move(to: CGPoint(x: 6.5, y: 8.8)); chevron.addLine(to: CGPoint(x: 10, y: 12.3)); chevron.addLine(to: CGPoint(x: 13.5, y: 8.8))
            stroke(ctx, chevron)
        case .drag:
            for x in [7.0, 13.0] as [CGFloat] {
                for y in [5.0, 10.0, 15.0] as [CGFloat] {
                    fill(ctx, CGPath(ellipseIn: CGRect(x: x - 1.5, y: y - 1.5, width: 3, height: 3), transform: nil))
                }
            }
        case .more:
            for x in [4.5, 10.0, 15.5] as [CGFloat] {
                fill(ctx, CGPath(ellipseIn: CGRect(x: x - 1.6, y: 8.4, width: 3.2, height: 3.2), transform: nil))
            }
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
        case .fill(let mode, let ellipse):
            let r = CGRect(x: 3, y: 4.5, width: 14, height: 11)
            let shape = ellipse ? CGPath(ellipseIn: r, transform: nil) : CGPath(roundedRect: r, cornerWidth: 2, cornerHeight: 2, transform: nil)
            switch mode {
            case .outline: stroke(ctx, shape)
            case .filled: fill(ctx, shape)
            case .outlineTranslucentFill:
                fill(ctx, shape, alpha: 0.35)
                stroke(ctx, shape)
            }
        case .dash(let d):
            stroke(ctx, line(CGPoint(x: 3, y: 10), CGPoint(x: 17, y: 10)), width: 2, dash: d == .dashed ? [3, 3] : [])
        case .textDecoration(let d):
            let pill = CGPath(roundedRect: CGRect(x: 1.5, y: 4, width: 17, height: 12), cornerWidth: 6, cornerHeight: 6, transform: nil)
            switch d {
            case .plain: letter(ctx, "A", size: 14, weight: .semibold, center: CGPoint(x: 10, y: 10))
            case .outlined: letter(ctx, "A", size: 14, weight: .heavy, center: CGPoint(x: 10, y: 10), outlined: true)
            case .solidPill:
                fill(ctx, pill)
                letter(ctx, "A", size: 10.5, weight: .bold, center: CGPoint(x: 10, y: 10), knockout: true)
            case .translucentPill:
                fill(ctx, pill, alpha: 0.35)
                letter(ctx, "A", size: 10.5, weight: .bold, center: CGPoint(x: 10, y: 10))
            }
        case .textAlign(let a):
            let widths: [CGFloat] = [14, 9, 12, 8]
            let p = CGMutablePath()
            for (i, w) in widths.enumerated() {
                let y = 4.5 + CGFloat(i) * 3.7
                let x: CGFloat = switch a {
                case .left: 3
                case .center: 10 - w / 2
                case .right: 17 - w
                }
                p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + w, y: y))
            }
            stroke(ctx, p)
        case .bold:
            letter(ctx, "B", size: 14, weight: .black, center: CGPoint(x: 10, y: 10))
        case .highlightFreehand:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 3.5, y: 13))
            p.addCurve(to: CGPoint(x: 16.5, y: 7), control1: CGPoint(x: 8, y: 4), control2: CGPoint(x: 11, y: 16))
            stroke(ctx, p, width: 4.5)
        case .highlightRect:
            let r = CGPath(roundedRect: CGRect(x: 2.5, y: 6, width: 15, height: 8), cornerWidth: 1.5, cornerHeight: 1.5, transform: nil)
            fill(ctx, r, alpha: 0.5)
            stroke(ctx, line(CGPoint(x: 5, y: 10), CGPoint(x: 15, y: 10)), width: 1.4)
        case .thickness(let step):
            let d: [CGFloat] = [2.5, 4.5, 6.5, 9, 12]
            let s = d[min(max(step, 0), d.count - 1)]
            fill(ctx, CGPath(ellipseIn: CGRect(x: 10 - s / 2, y: 10 - s / 2, width: s, height: s), transform: nil))
        case .opacity:
            stroke(ctx, CGPath(ellipseIn: CGRect(x: 3, y: 3, width: 14, height: 14), transform: nil))
            let half = CGMutablePath()
            half.addArc(center: CGPoint(x: 10, y: 10), radius: 7, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            half.closeSubpath()
            fill(ctx, half)
        case .cornerRadius:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 4, y: 17)); p.addLine(to: CGPoint(x: 4, y: 10))
            p.addArc(tangent1End: CGPoint(x: 4, y: 4), tangent2End: CGPoint(x: 10, y: 4), radius: 6)
            p.addLine(to: CGPoint(x: 17, y: 4))
            stroke(ctx, p)
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
        case .padding:
            stroke(ctx, CGPath(roundedRect: CGRect(x: 2.5, y: 2.5, width: 15, height: 15), cornerWidth: 2.5, cornerHeight: 2.5, transform: nil), dash: [2, 2])
            fill(ctx, CGPath(roundedRect: CGRect(x: 6.5, y: 6.5, width: 7, height: 7), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        }
    }
}
