import CoreGraphics
import Foundation

public enum AnnotationRenderer {
    public enum RenderError: Error, Sendable { case contextCreationFailed }

    /// Draws one object. The single source of truth for how objects look;
    /// used by the editor's layers and by export. `ctx` is in base-image
    /// pixel space with a top-left origin.
    public static func draw(
        _ object: AnnotationObject, in ctx: CGContext, document: AnnotationDocument, base: BaseImageProvider
    ) {
        draw(object, in: ctx, document: document, base: base, quality: .final)
    }

    /// As `draw(_:in:document:base:)`, with a quality choice (use `.preview` while dragging a redaction).
    public static func draw(
        _ object: AnnotationObject, in ctx: CGContext, document: AnnotationDocument, base: BaseImageProvider,
        quality: RenderQuality
    ) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setShouldAntialias(true)
        ctx.setAllowsAntialiasing(true)
        let style = object.style
        switch object.shape {
        case .arrow(let g):
            drawArrow(g, style: style, in: ctx)
        case .rectangle(let rect, let radius):
            drawBox(rect, cornerRadius: radius, ellipse: false, style: style, in: ctx)
        case .ellipse(let rect):
            drawBox(rect, cornerRadius: 0, ellipse: true, style: style, in: ctx)
        case .line(let s, let e):
            drawLine(s, e, style: style, in: ctx)
        case .text(let box):
            drawText(box, style: style, in: ctx)
        case .highlight(let h):
            drawHighlight(h, style: style, in: ctx)
        case .redact(let rect, let mode):
            drawRedaction(rect, mode: mode, style: style, document: document, base: base, quality: quality, in: ctx)
        case .counter(let c):
            drawCounter(c, style: style, in: ctx)
        case .pen(let pts):
            drawPen(pts, style: style, in: ctx)
        }
    }

    /// Blend mode an object needs against what is beneath it. The editor should mirror this on
    /// the object's layer (e.g. `compositingFilter = "multiplyBlendMode"` for highlights),
    /// because a separate layer cannot multiply against the image by itself.
    public static func blendMode(for object: AnnotationObject) -> CGBlendMode {
        if case .highlight = object.shape { return .multiply }
        return .normal
    }

    /// Objects in paint order: redactions first (SPEC §5.3), then everything else in z-order.
    public static func paintOrder(_ objects: [AnnotationObject]) -> [AnnotationObject] {
        objects.filter(\.isRedaction) + objects.filter { !$0.isRedaction }
    }

    /// Full flattened image at base-image pixel resolution (× outputScale).
    public static func renderImage(
        _ document: AnnotationDocument, base: BaseImageProvider, outputScale: CGFloat
    ) throws -> CGImage {
        try renderImage(document, base: base, outputScale: outputScale, opaqueMatte: nil)
    }

    /// `opaqueMatte`: composite onto this colour first (for formats without alpha, e.g. JPEG).
    static func renderImage(
        _ document: AnnotationDocument, base: BaseImageProvider, outputScale rawScale: CGFloat, opaqueMatte: RGBAColor?
    ) throws -> CGImage {
        let image = try base.image()
        let outputScale = rawScale > 0 ? rawScale : 1
        let layout = BackgroundLayout(document: document, visibleContent: visibleContent(document, base: base))
        let width = max(Int((layout.canvasSize.width * outputScale).rounded()), 1)
        let height = max(Int((layout.canvasSize.height * outputScale).rounded()), 1)
        let space = Redactor.workingSpace(of: image)
        guard let ctx = Redactor.bitmap(width: width, height: height, space: space) else {
            throw RenderError.contextCreationFailed
        }
        ctx.interpolationQuality = .high
        // Flip to a top-left-origin canvas space.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: outputScale, y: -outputScale)
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        if let opaqueMatte {
            ctx.setFillColor(opaqueMatte.cgColor)
            ctx.fill(canvas)
        }
        if let background = document.background {
            drawBackgroundFill(background.fill, in: canvas, ctx: ctx)
        }

        // Image group: base image, redactions, objects; clipped to the visible image with the
        // background's corner radius, over its drop shadow.
        let rect = document.imageRect
        let radius = min(document.background?.cornerRadius ?? 0, min(rect.width, rect.height) / 2)
        if let bg = document.background, let shadow = shadowParameters(bg.shadow, imageSize: rect.size) {
            drawShadow(shadow, image: image, document: document, layout: layout, radius: radius, outputScale: outputScale, in: ctx)
        }
        ctx.saveGState()
        ctx.translateBy(x: layout.imageFrame.minX - rect.minX, y: layout.imageFrame.minY - rect.minY)
        if radius > 0 {
            ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        } else {
            ctx.addRect(rect)
        }
        ctx.clip()
        ctx.drawFlipped(image, in: CGRect(origin: .zero, size: document.pixelSize))
        for object in paintOrder(document.objects) {
            draw(object, in: ctx, document: document, base: base, quality: .final)
        }
        ctx.restoreGState()

        guard let output = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return output
    }

    /// The visible-content rect used for auto-balance, relative to the crop's origin.
    static func visibleContent(_ document: AnnotationDocument, base: BaseImageProvider) -> CGRect? {
        guard let bg = document.background, bg.autoBalance, let visible = base.visibleContentBounds() else { return nil }
        let rect = document.imageRect
        let r = visible.intersection(rect)
        guard !r.isEmpty else { return nil }
        return r.offsetBy(dx: -rect.minX, dy: -rect.minY)
    }

    /// Dirty rect including stroke, heads, outlines, pills and shadows.
    public static func bounds(of object: AnnotationObject) -> CGRect {
        let style = object.style
        let w = style.lineWidth
        let r: CGRect
        switch object.shape {
        case .arrow(let g):
            let path = ArrowPath.make(g, width: w)
            r = path.boundingBox(extraWidth: style.contrastOutline ? 2 * contrastOutlineWidth(lineWidth: w) : 0)
        case .rectangle(let rect, _), .ellipse(let rect):
            r = style.fill == .filled ? rect.standardized : rect.standardized.insetBy(dx: -w / 2, dy: -w / 2)
        case .line(let s, let e):
            r = Geometry.rect(s, e).insetBy(dx: -w / 2, dy: -w / 2)
        case .text(let box):
            let layout = TextLayout(box: box, fontSize: style.fontSize)
            r = layout.frame.insetBy(dx: -TextLayout.outlineWidth(fontSize: style.fontSize), dy: -TextLayout.outlineWidth(fontSize: style.fontSize))
        case .highlight(.freehand(let pts)), .pen(let pts):
            r = StrokeSmoothing.path(through: pts).boundingBoxOfPath.insetBy(dx: -w / 2, dy: -w / 2)
        case .highlight(.rect(let rect)), .redact(let rect, _):
            r = rect.standardized
        case .counter(let c):
            r = CounterShape(c, radius: style.fontSize).bounds
        }
        // One pixel of slack for antialiasing.
        return r.insetBy(dx: -1, dy: -1)
    }

    static func rectContaining(_ points: [CGPoint]) -> CGRect { Geometry.rectContaining(points) }
}
