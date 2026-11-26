import CoreGraphics

// Arrows, boxes, lines, pen and highlighter.
extension AnnotationRenderer {
    /// Runs `body` with opaque colours inside a transparency layer when the object is
    /// translucent, so overlapping parts (head over shaft, outline over fill) don't double up.
    static func withObjectAlpha(_ alpha: CGFloat, bounds: CGRect, in ctx: CGContext, _ body: () -> Void) {
        if alpha >= 0.999 {
            body()
            return
        }
        ctx.saveGState()
        ctx.setAlpha(max(alpha, 0))
        ctx.beginTransparencyLayer(in: bounds, auxiliaryInfo: nil)
        body()
        ctx.endTransparencyLayer()
        ctx.restoreGState()
    }

    static func effectiveAlpha(_ style: ObjectStyle) -> CGFloat {
        min(max(style.color.alpha * style.opacity, 0), 1)
    }

    static func contrastOutlineWidth(lineWidth w: CGFloat) -> CGFloat { max(w * 0.32, 1.25) }

    static func contrastOutlineColor(for color: RGBAColor) -> CGColor {
        color.luminance > 0.5
            ? CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55)
            : CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92)
    }

    static func drawArrow(_ g: ArrowGeometry, style: ObjectStyle, in ctx: CGContext) {
        let arrow = ArrowPath.make(g, width: style.lineWidth)
        let opaque = style.color.withAlpha(1).cgColor
        let outline = style.contrastOutline ? contrastOutlineWidth(lineWidth: style.lineWidth) : 0
        let box = arrow.boundingBox(extraWidth: 2 * outline).insetBy(dx: -2, dy: -2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        withObjectAlpha(effectiveAlpha(style), bounds: box, in: ctx) {
            if outline > 0 {
                ctx.setFillColor(contrastOutlineColor(for: style.color))
                for path in arrow.silhouettes(extraWidth: 2 * outline) {
                    ctx.addPath(path)
                    ctx.fillPath()
                }
            }
            ctx.setFillColor(opaque)
            for path in arrow.silhouettes() {
                ctx.addPath(path)
                ctx.fillPath()
            }
        }
    }

    static func boxPath(_ rect: CGRect, cornerRadius: CGFloat, ellipse: Bool) -> CGPath {
        let r = rect.standardized
        if ellipse { return CGPath(ellipseIn: r, transform: nil) }
        let radius = min(max(cornerRadius, 0), min(r.width, r.height) / 2)
        return radius > 0
            ? CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
            : CGPath(rect: r, transform: nil)
    }

    static func applyDash(_ style: ObjectStyle, in ctx: CGContext) {
        guard style.dash == .dashed else { return }
        let w = max(style.lineWidth, 0.5)
        // Round caps add w to every dash, so the visible dash is ~3w and the gap ~1.6w.
        ctx.setLineDash(phase: 0, lengths: [w * 2, w * 2.6])
    }

    static func drawBox(_ rect: CGRect, cornerRadius: CGFloat, ellipse: Bool, style: ObjectStyle, in ctx: CGContext) {
        let path = boxPath(rect, cornerRadius: cornerRadius, ellipse: ellipse)
        let opaque = style.color.withAlpha(1).cgColor
        let w = style.lineWidth
        withObjectAlpha(effectiveAlpha(style), bounds: rect.standardized.insetBy(dx: -w - 2, dy: -w - 2), in: ctx) {
            switch style.fill {
            case .filled:
                ctx.setFillColor(opaque)
                ctx.addPath(path)
                ctx.fillPath()
            case .outline, .outlineTranslucentFill:
                if style.fill == .outlineTranslucentFill {
                    ctx.setFillColor(style.color.withAlpha(0.22).cgColor)
                    ctx.addPath(path)
                    ctx.fillPath()
                }
                ctx.setStrokeColor(opaque)
                ctx.setLineWidth(w)
                ctx.setLineJoin(cornerRadius > 0 || ellipse ? .round : .miter)
                ctx.setLineCap(style.dash == .dashed ? .round : .butt)
                applyDash(style, in: ctx)
                ctx.addPath(path)
                ctx.strokePath()
            }
        }
    }

    static func drawLine(_ s: CGPoint, _ e: CGPoint, style: ObjectStyle, in ctx: CGContext) {
        let w = style.lineWidth
        withObjectAlpha(effectiveAlpha(style), bounds: Geometry.rect(s, e).insetBy(dx: -w - 2, dy: -w - 2), in: ctx) {
            ctx.setStrokeColor(style.color.withAlpha(1).cgColor)
            ctx.setLineWidth(w)
            ctx.setLineCap(.round)
            applyDash(style, in: ctx)
            ctx.move(to: s)
            ctx.addLine(to: e)
            ctx.strokePath()
        }
    }

    static func drawPen(_ points: [CGPoint], style: ObjectStyle, in ctx: CGContext) {
        guard !points.isEmpty else { return }
        let path = StrokeSmoothing.path(through: points)
        let w = style.lineWidth
        // A single stroked path never overlaps itself in coverage, so plain alpha is exact.
        ctx.setStrokeColor(style.color.scaledAlpha(style.opacity).cgColor)
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        applyDash(style, in: ctx)
        ctx.addPath(path)
        ctx.strokePath()
    }

    static func drawHighlight(_ h: HighlightGeometry, style: ObjectStyle, in ctx: CGContext) {
        // Multiply keeps dark text under the mark readable (SPEC §5.3).
        ctx.setBlendMode(.multiply)
        let color = style.color.scaledAlpha(style.opacity).cgColor
        switch h {
        case .freehand(let points):
            guard !points.isEmpty else { return }
            ctx.setStrokeColor(color)
            ctx.setLineWidth(style.lineWidth)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.addPath(StrokeSmoothing.path(through: points))
            ctx.strokePath()
        case .rect(let rect):
            let r = rect.standardized
            let radius = min(r.width, r.height) * 0.12
            ctx.setFillColor(color)
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
            ctx.fillPath()
        }
    }
}
