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
            drawHighlight(h, style: style, blend: blendMode(for: object, document: document, base: base), in: ctx)
        case .redact(let rect, let mode):
            drawRedaction(rect, mode: mode, style: style, document: document, base: base, quality: quality, in: ctx)
        case .counter(let c):
            drawCounter(c, style: style, in: ctx)
        case .pen(let pts):
            drawPen(pts, style: style, in: ctx)
        }
    }

    /// Blend mode an object needs against what is beneath it, assuming light content. Prefer
    /// `blendMode(for:document:base:)`, which also handles highlights over dark content.
    public static func blendMode(for object: AnnotationObject) -> CGBlendMode {
        if case .highlight = object.shape { return .multiply }
        return .normal
    }

    /// Blend mode an object needs against the base image beneath it. Highlights multiply, so dark
    /// text under the mark stays crisp; over dark content (average luminance < 0.18, e.g. a dark-mode
    /// window) multiply would make the mark invisible, so they screen instead, which keeps light
    /// text readable and the mark visible. The editor must mirror this on the object's layer:
    /// `compositingFilter = "multiplyBlendMode"` / `"screenBlendMode"`, since a separate layer
    /// cannot blend with the image by itself.
    public static func blendMode(for object: AnnotationObject, document: AnnotationDocument, base: BaseImageProvider) -> CGBlendMode {
        guard case .highlight = object.shape else { return .normal }
        let area = ObjectGeometry.frame(of: object).insetBy(dx: -object.style.lineWidth / 2, dy: -object.style.lineWidth / 2)
        if let l = base.averageLuminance(in: area, imageSize: document.pixelSize), l < darkContentLuminance { return .screen }
        return .multiply
    }

    /// Below this average base luminance a highlight switches from multiply to screen.
    public static let darkContentLuminance: CGFloat = 0.18

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
        let layout = backgroundLayout(document, base: base)
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
        drawBackground(document, base: base, image: image, layout: layout, skipUnderImage: true, in: ctx)

        // Image group: base image, redactions, objects; clipped to the visible image with the
        // background's inner corner radius (`imageCornerRadius`).
        let rect = document.imageRect
        let radius = imageCornerRadius(document)
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

    /// Draws the presentation background only: the fill over the whole canvas and the image's
    /// drop shadow, no image or objects. Exactly what export draws beneath the image, so an editor
    /// preview matches. `ctx` is in top-left canvas space (`BackgroundLayout.canvasSize`, base-image
    /// pixels); scale the CTM for zoom. Does nothing when the document has no background.
    public static func drawBackground(_ document: AnnotationDocument, base: BaseImageProvider, in ctx: CGContext) {
        guard document.background != nil, let image = try? base.image() else { return } // unreadable base: no shadow shape
        drawBackground(document, base: base, image: image, layout: backgroundLayout(document, base: base), in: ctx)
    }

    /// As `drawBackground(_:base:in:)`, with `ctx` in top-left *device* space at `scale` device
    /// pixels per canvas pixel (e.g. backing scale × zoom); the CTM is scaled for the call.
    public static func drawBackground(document: AnnotationDocument, base: BaseImageProvider, in ctx: CGContext, scale: CGFloat) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.scaleBy(x: scale, y: scale)
        drawBackground(document, base: base, in: ctx)
    }

    /// The background layout for `document`, using the provider's visible-content bounds for auto-balance.
    public static func backgroundLayout(_ document: AnnotationDocument, base: BaseImageProvider) -> BackgroundLayout {
        BackgroundLayout(document: document, visibleContent: visibleContent(document, base: base))
    }

    /// Inner corner radius applied to the image (0 without a background), clamped to the crop.
    public static func imageCornerRadius(_ document: AnnotationDocument) -> CGFloat {
        let rect = document.imageRect
        return max(min(document.background?.cornerRadius ?? 0, min(rect.width, rect.height) / 2), 0)
    }

    /// `skipUnderImage`: export passes true (see `backgroundRegions`).
    static func drawBackground(_ document: AnnotationDocument, base: BaseImageProvider, image: CGImage,
                               layout: BackgroundLayout, skipUnderImage: Bool = false, in ctx: CGContext) {
        guard let bg = document.background else { return }
        let canvas = CGRect(origin: .zero, size: layout.canvasSize)
        let shadow = shadowParameters(bg.shadow, imageSize: document.imageRect.size)
        let shadowImage = shadow.flatMap { renderShadow($0, image: image, document: document, layout: layout, radius: imageCornerRadius(document), base: base) }
        // Each region is drawn under its own rectangular clip: Core Graphics rasterises a
        // gradient over the clip's bounding box, so one band at a time is what saves the work.
        for region in backgroundRegions(document, layout: layout, canvas: canvas, skipUnderImage: skipUnderImage, base: base) {
            ctx.saveGState()
            ctx.clip(to: region)
            drawBackgroundFill(bg.fill, in: canvas, ctx: ctx)
            if let shadowImage { drawShadowImage(shadowImage, in: ctx) }
            ctx.restoreGState()
        }
    }

    /// The whole canvas, or, for an opaque image during export, four bands around the image's
    /// inner rect (inset past its corner radius so rounded corners still get fill and shadow);
    /// nothing under an opaque image can show.
    static func backgroundRegions(_ document: AnnotationDocument, layout: BackgroundLayout, canvas: CGRect,
                                  skipUnderImage: Bool, base: BaseImageProvider) -> [CGRect] {
        let r = imageCornerRadius(document)
        let inner = layout.imageFrame.insetBy(dx: r + 1, dy: r + 1).intersection(canvas)
        guard skipUnderImage, !inner.isEmpty, base.isOpaque() else { return [canvas] }
        return [
            CGRect(x: canvas.minX, y: canvas.minY, width: canvas.width, height: inner.minY - canvas.minY),
            CGRect(x: canvas.minX, y: inner.maxY, width: canvas.width, height: canvas.maxY - inner.maxY),
            CGRect(x: canvas.minX, y: inner.minY, width: inner.minX - canvas.minX, height: inner.height),
            CGRect(x: inner.maxX, y: inner.minY, width: canvas.maxX - inner.maxX, height: inner.height),
        ].filter { $0.width > 0 && $0.height > 0 }
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
