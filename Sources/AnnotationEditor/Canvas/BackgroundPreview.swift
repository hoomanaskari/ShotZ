import AnnotationKit
import CoreGraphics

/// The canvas's background layer: AnnotationKit's own background fill and drop shadow
/// (the code export runs), rendered into one small bitmap that the GPU scales up.
enum BackgroundPreview {
    /// Longest side of the preview bitmap (fills and shadows are smooth).
    static let maxSide: CGFloat = 1024

    static func render(document: AnnotationDocument, layout: CanvasLayout, base: BaseImageProvider) -> CGImage? {
        guard layout.background != nil else { return nil }
        let canvas = layout.extent
        let k = min(1, maxSide / max(canvas.width, canvas.height, 1))
        let w = max(Int((canvas.width * k).rounded(.up)), 1), h = max(Int((canvas.height * k).rounded(.up)), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Top-left device space; AnnotationKit scales the CTM by `k`.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        AnnotationRenderer.drawBackground(document: document, base: base, in: ctx, scale: k)
        return ctx.makeImage()
    }
}
