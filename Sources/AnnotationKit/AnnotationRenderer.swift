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
        // TODO(engineer C): real drawing for every shape. Minimal placeholder strokes only.
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setStrokeColor(object.style.color.withAlpha(object.style.color.alpha * object.style.opacity).cgColor)
        ctx.setLineWidth(object.style.lineWidth)
        ctx.stroke(bounds(of: object).insetBy(dx: object.style.lineWidth, dy: object.style.lineWidth))
    }

    /// Full flattened image at base-image pixel resolution (× outputScale).
    public static func renderImage(
        _ document: AnnotationDocument, base: BaseImageProvider, outputScale: CGFloat
    ) throws -> CGImage {
        let image = try base.image()
        let rect = document.imageRect
        let width = Int((rect.width * outputScale).rounded())
        let height = Int((rect.height * outputScale).rounded())
        guard let ctx = CGContext(
            data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw RenderError.contextCreationFailed }

        // Flip to top-left origin pixel space, then translate for crop.
        ctx.translateBy(x: 0, y: CGFloat(height))
        ctx.scaleBy(x: outputScale, y: -outputScale)
        ctx.translateBy(x: -rect.minX, y: -rect.minY)

        // CGContext.draw expects bottom-up; draw the image un-flipped locally.
        ctx.saveGState()
        ctx.translateBy(x: 0, y: document.pixelSize.height)
        ctx.scaleBy(x: 1, y: -1)
        ctx.draw(image, in: CGRect(origin: .zero, size: document.pixelSize))
        ctx.restoreGState()

        // TODO(engineer C): background, redactions first, then other objects.
        for object in document.objects {
            draw(object, in: ctx, document: document, base: base)
        }
        guard let output = ctx.makeImage() else { throw RenderError.contextCreationFailed }
        return output
    }

    /// Dirty rect including stroke. TODO(engineer C): exact for text, arrow heads, curves.
    public static func bounds(of object: AnnotationObject) -> CGRect {
        let pad = object.style.lineWidth
        let raw: CGRect
        switch object.shape {
        case .arrow(let g):
            raw = rectContaining([g.start, g.end] + (g.control.map { [$0] } ?? []))
            return raw.insetBy(dx: -pad * 3, dy: -pad * 3)
        case .rectangle(let r, _), .ellipse(let r), .redact(let r, _), .highlight(.rect(let r)):
            raw = r.standardized
        case .line(let s, let e):
            raw = rectContaining([s, e])
        case .text(let box):
            let width = box.wrapWidth ?? CGFloat(max(box.string.count, 1)) * object.style.fontSize * 0.6
            let lines = CGFloat(max(box.string.split(separator: "\n", omittingEmptySubsequences: false).count, 1))
            raw = CGRect(origin: box.origin, size: CGSize(width: width, height: lines * object.style.fontSize * 1.25))
        case .highlight(.freehand(let pts)), .pen(let pts):
            raw = rectContaining(pts)
        case .counter(let c):
            let r = object.style.fontSize
            let circle = CGRect(x: c.center.x - r, y: c.center.y - r, width: 2 * r, height: 2 * r)
            raw = c.tail.map { circle.union(rectContaining([$0])) } ?? circle
        }
        return raw.insetBy(dx: -pad, dy: -pad)
    }

    static func rectContaining(_ points: [CGPoint]) -> CGRect {
        guard let first = points.first else { return .null }
        var minX = first.x, minY = first.y, maxX = first.x, maxY = first.y
        for p in points.dropFirst() {
            minX = min(minX, p.x); minY = min(minY, p.y)
            maxX = max(maxX, p.x); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
