import AnnotationKit
import CoreGraphics

// TEMP until AnnotationKit provides background layout (canvas size and image
// placement for a `BackgroundStyle`). The renderer's export must use the same
// rules, or the live preview will differ from the exported file. Pure; unit-tested.
enum BackgroundLayoutShim {
    struct Layout: Equatable {
        /// Full output canvas, origin zero, pixels.
        var canvasSize: CGSize
        /// Where the visible image (crop) sits on the canvas.
        var imageFrame: CGRect
    }

    /// - Parameters:
    ///   - imageSize: the visible image (crop) size in pixels.
    ///   - opaqueBounds: content bounds inside the image (for auto-balance on
    ///     window captures with transparent shadow margins), image-local; nil = whole image.
    static func layout(imageSize: CGSize, style: BackgroundStyle, opaqueBounds: CGRect? = nil) -> Layout {
        let w = imageSize.width, h = imageSize.height
        let pad = max(0, min(style.padding, 0.25)) * max(w, h)
        var canvas = CGSize(width: w + 2 * pad, height: h + 2 * pad)
        if let ratio = style.aspect.ratio {
            if canvas.width / max(canvas.height, 1) < ratio {
                canvas.width = canvas.height * ratio
            } else {
                canvas.height = canvas.width / ratio
            }
        }
        let freeX = canvas.width - w, freeY = canvas.height - h
        let (fx, fy) = fractions(style.alignment)
        let margin = pad * 0.3
        func place(_ free: CGFloat, _ f: CGFloat) -> CGFloat {
            f == 0.5 ? free / 2 : margin + max(free - 2 * margin, 0) * f
        }
        var x = place(freeX, fx), y = place(freeY, fy)
        if style.autoBalance, let content = opaqueBounds, !content.isEmpty {
            // Centre the visible content rather than the transparent margin.
            x += (w / 2 - content.midX) * (fx == 0.5 ? 1 : 0)
            y += (h / 2 - content.midY) * (fy == 0.5 ? 1 : 0)
        }
        return Layout(
            canvasSize: CGSize(width: canvas.width.rounded(), height: canvas.height.rounded()),
            imageFrame: CGRect(x: x.rounded(), y: y.rounded(), width: w, height: h)
        )
    }

    static func fractions(_ a: BackgroundStyle.Alignment) -> (CGFloat, CGFloat) {
        switch a {
        case .topLeft: (0, 0)
        case .top: (0.5, 0)
        case .topRight: (1, 0)
        case .left: (0, 0.5)
        case .center: (0.5, 0.5)
        case .right: (1, 0.5)
        case .bottomLeft: (0, 1)
        case .bottom: (0.5, 1)
        case .bottomRight: (1, 1)
        }
    }
}
