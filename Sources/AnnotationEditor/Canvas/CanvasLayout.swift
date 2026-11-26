import AnnotationKit
import CoreGraphics

/// Where things sit in the canvas document view. The document view's
/// coordinate space is "canvas units" (1 unit = 1 base-image pixel, origin
/// top-left of the visible canvas); base-image pixel space is offset from it.
/// Pure; unit-tested.
struct CanvasLayout: Equatable {
    /// Size of the document view in units.
    var extent: CGSize
    /// canvas point = image pixel point + offset.
    var offset: CGVector
    /// Background canvas (in canvas units) when a background is shown.
    var background: BackgroundStyle?
    /// The visible image area in canvas units.
    var imageFrame: CGRect

    /// - Parameter editingCrop: the crop tool shows the whole image without background.
    static func make(document: AnnotationDocument, editingCrop: Bool, opaqueBounds: CGRect? = nil) -> CanvasLayout {
        let full = CGRect(origin: .zero, size: document.pixelSize)
        if editingCrop {
            return CanvasLayout(extent: full.size, offset: .zero, background: nil, imageFrame: full)
        }
        let visible = document.imageRect
        if let bg = document.background {
            let local = opaqueBounds.map { $0.offsetBy(dx: -visible.minX, dy: -visible.minY).intersection(CGRect(origin: .zero, size: visible.size)) }
            let l = BackgroundLayoutShim.layout(imageSize: visible.size, style: bg, opaqueBounds: local)
            return CanvasLayout(
                extent: l.canvasSize,
                offset: CGVector(dx: l.imageFrame.minX - visible.minX, dy: l.imageFrame.minY - visible.minY),
                background: bg,
                imageFrame: l.imageFrame
            )
        }
        return CanvasLayout(
            extent: visible.size,
            offset: CGVector(dx: -visible.minX, dy: -visible.minY),
            background: nil,
            imageFrame: CGRect(origin: .zero, size: visible.size)
        )
    }

    func toCanvas(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x + offset.dx, y: p.y + offset.dy) }
    func toImage(_ p: CGPoint) -> CGPoint { CGPoint(x: p.x - offset.dx, y: p.y - offset.dy) }
    func toCanvas(_ r: CGRect) -> CGRect { r.offsetBy(dx: offset.dx, dy: offset.dy) }
}
