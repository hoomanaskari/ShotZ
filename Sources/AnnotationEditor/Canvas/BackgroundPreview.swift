import AnnotationKit
import CoreGraphics

// TEMP until AnnotationKit exposes its background + shadow drawing publicly
// (`AnnotationRenderer.drawShadow` / `shadowParameters` are internal today).
// Renders the background fill and the image group's drop shadow into one small
// bitmap for the canvas's background layer. The fill uses AnnotationKit's public
// `drawBackgroundFill`; the shadow mirrors AnnotationKit's constants so the live
// preview matches the exported file.
enum BackgroundPreview {
    /// Longest side of the preview bitmap (fills and shadows are smooth; the GPU scales it up).
    static let maxSide: CGFloat = 1024

    static func render(document: AnnotationDocument, layout: CanvasLayout, image: CGImage) -> CGImage? {
        guard let bg = layout.background else { return nil }
        let canvas = layout.extent
        let k = min(1, maxSide / max(canvas.width, canvas.height, 1))
        let w = max(Int((canvas.width * k).rounded(.up)), 1), h = max(Int((canvas.height * k).rounded(.up)), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: k, y: -k)
        AnnotationRenderer.drawBackgroundFill(bg.fill, in: CGRect(origin: .zero, size: canvas), ctx: ctx)

        let visible = document.imageRect
        let radius = min(bg.cornerRadius, min(visible.width, visible.height) / 2)
        if let shadow = shadow(bg.shadow, imageSize: visible.size) {
            ctx.saveGState()
            // In this flipped context a positive y offset in user space casts downwards.
            ctx.setShadow(offset: CGSize(width: shadow.offset.width * k, height: -shadow.offset.height * k),
                          blur: shadow.blur * k, color: shadow.color)
            let frame = layout.imageFrame
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast:
                let path = radius > 0
                    ? CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
                    : CGPath(rect: frame, transform: nil)
                ctx.addPath(path)
                ctx.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
                ctx.fillPath()
            default:
                // Window captures cast their real silhouette.
                if let cropped = image.cropping(to: visible.integral) {
                    ctx.translateBy(x: frame.minX, y: frame.maxY)
                    ctx.scaleBy(x: 1, y: -1)
                    ctx.draw(cropped, in: CGRect(origin: .zero, size: frame.size))
                }
            }
            ctx.restoreGState()
        }
        return ctx.makeImage()
    }

    /// Mirrors AnnotationKit's shadow parameters (offset and blur scale with the image's long edge).
    static func shadow(_ s: AnnotationKit.BackgroundStyle.Shadow, imageSize: CGSize) -> (offset: CGSize, blur: CGFloat, color: CGColor)? {
        let long = max(imageSize.width, imageSize.height)
        switch s {
        case .off: return nil
        case .soft: return (CGSize(width: 0, height: long * 0.006), long * 0.022, CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
        case .strong: return (CGSize(width: 0, height: long * 0.024), long * 0.06, CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.55))
        }
    }
}
