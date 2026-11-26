import CoreGraphics
import CoreText

// Text, counters and redactions.
extension AnnotationRenderer {
    static func drawText(_ box: TextBox, style: ObjectStyle, in ctx: CGContext) {
        guard !box.string.isEmpty else { return }
        let size = style.fontSize
        let color = style.color.withAlpha(1)
        let measure = TextLayout(box: box, fontSize: size)
        let outline = TextLayout.outlineWidth(fontSize: size)
        let area = measure.frame.insetBy(dx: -outline - 2, dy: -outline - 2)
        withObjectAlpha(effectiveAlpha(style), bounds: area, in: ctx) {
            var textColor = color
            switch box.style.decoration {
            case .plain:
                break
            case .outlined:
                let halo = color.luminance > 0.5 ? RGBAColor(red: 0, green: 0, blue: 0, alpha: 0.85) : RGBAColor.white
                ctx.setLineJoin(.round)
                TextLayout(box: box, fontSize: size, color: halo.cgColor, stroke: (halo.cgColor, outline)).drawGlyphs(in: ctx)
            case .solidPill:
                fillPill(measure, color: color.cgColor, in: ctx)
                textColor = color.contrastingTextColor
            case .translucentPill:
                // Tinted glass: the chosen colour, see-through, with auto-contrast text.
                fillPill(measure, color: color.withAlpha(0.7).cgColor, in: ctx)
                textColor = color.contrastingTextColor
            }
            TextLayout(box: box, fontSize: size, color: textColor.cgColor, stroke: nil).drawGlyphs(in: ctx)
        }
    }

    private static func fillPill(_ layout: TextLayout, color: CGColor, in ctx: CGContext) {
        let r = TextLayout.pillRadius(for: layout.frame, fontSize: layout.fontSize)
        ctx.setFillColor(color)
        ctx.addPath(CGPath(roundedRect: layout.frame, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.fillPath()
    }

    static func drawCounter(_ c: CounterGeometry, style: ObjectStyle, in ctx: CGContext) {
        let shape = CounterShape(c, radius: style.fontSize)
        let fill = style.color.withAlpha(1)
        withObjectAlpha(effectiveAlpha(style), bounds: shape.bounds.insetBy(dx: -2, dy: -2), in: ctx) {
            // Soft drop shadow and a light ring keep the badge legible on any background.
            ctx.saveGState()
            ctx.setShadowInUserSpace(offset: shape.shadowOffset, blur: shape.shadowBlur,
                                     color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
            ctx.setFillColor(fill.cgColor)
            ctx.addPath(shape.path)
            ctx.fillPath()
            ctx.restoreGState()
            ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: fill.luminance > 0.8 ? 0 : 0.9))
            ctx.setLineWidth(shape.ringWidth)
            ctx.setLineJoin(.round)
            ctx.addPath(shape.path)
            ctx.strokePath()
            drawCounterLabel(c.label, center: c.center, radius: shape.radius, color: fill.contrastingTextColor, in: ctx)
        }
    }

    private static func drawCounterLabel(_ label: String, center: CGPoint, radius: CGFloat, color: RGBAColor, in ctx: CGContext) {
        // Shrink long labels ("12", "AB") so they stay inside the badge.
        var size = radius * 1.12
        let maxWidth = radius * 1.45
        var line: CTLine
        var glyphBounds: CGRect
        repeat {
            let attrs: [CFString: Any] = [
                kCTFontAttributeName: TextLayout.font(size: size, bold: true),
                kCTForegroundColorAttributeName: color.cgColor,
            ]
            line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, label as CFString, attrs as CFDictionary))
            glyphBounds = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
            size *= 0.92
        } while glyphBounds.width > maxWidth && size > radius * 0.4
        ctx.saveGState()
        // Centre the glyph ink, not the typographic box, so digits sit optically centred.
        ctx.translateBy(x: center.x - glyphBounds.midX, y: center.y + glyphBounds.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textMatrix = .identity
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }

    static func drawRedaction(_ rect: CGRect, mode: RedactMode, style: ObjectStyle, document: AnnotationDocument,
                              base: BaseImageProvider, quality: RenderQuality, in ctx: CGContext) {
        let target = BaseImageProvider.pixelRect(rect, imageSize: document.pixelSize)
        guard !target.isEmpty else { return }
        switch mode.kind {
        case .solid:
            // Always fully opaque: a redaction must never let pixels through.
            ctx.setFillColor(style.color.withAlpha(1).cgColor)
            ctx.fill(target)
        case .pixelate, .blur:
            ctx.interpolationQuality = .none
            if quality == .final, let img = base.redactedImage(rect: target, mode: mode, scale: document.scale) {
                ctx.drawFlipped(img, in: target)
            } else if let preview = previewRedaction(target, mode: mode, document: document, base: base) {
                ctx.interpolationQuality = mode.kind == .blur ? .high : .none
                ctx.drawFlipped(preview, in: target)
            } else {
                // Never show the original pixels: fall back to an opaque neutral fill.
                ctx.setFillColor(CGColor(srgbRed: 0.5, green: 0.5, blue: 0.52, alpha: 1))
                ctx.fill(target)
            }
        }
    }

    /// Cheap approximation from the downsampled preview image: a tiny bitmap with one pixel per
    /// block (pixelate) or per blur radius (blur), stretched over the rect by the caller.
    private static func previewRedaction(_ target: CGRect, mode: RedactMode, document: AnnotationDocument,
                                         base: BaseImageProvider) -> CGImage? {
        guard let preview = base.previewImage(), document.pixelSize.width > 0 else { return nil }
        let k = CGFloat(preview.width) / document.pixelSize.width
        let src = CGRect(x: target.minX * k, y: target.minY * k, width: target.width * k, height: target.height * k)
            .integral.intersection(CGRect(x: 0, y: 0, width: preview.width, height: preview.height))
        guard !src.isEmpty, let crop = preview.cropping(to: src) else { return nil }
        let cell = mode.kind == .pixelate
            ? Redactor.blockSize(strength: mode.strength, scale: document.scale)
            : Redactor.blurRadius(strength: mode.strength, scale: document.scale) * 0.75
        let cols = max(Int((target.width / cell).rounded()), 1), rows = max(Int((target.height / cell).rounded()), 1)
        guard let small = Redactor.bitmap(width: cols, height: rows, space: Redactor.workingSpace(of: preview)) else { return nil }
        small.interpolationQuality = .high
        small.draw(crop, in: CGRect(x: 0, y: 0, width: cols, height: rows))
        return small.makeImage()
    }
}
