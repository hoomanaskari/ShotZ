import CoreGraphics

/// Where the (cropped) image sits on the output canvas when a background is on (SPEC §5.4).
/// All values are in base-image pixels (multiply by the output scale for the final bitmap).
public struct BackgroundLayout: Sendable, Equatable {
    /// Full output size. Without a background this is the crop size.
    public var canvasSize: CGSize
    /// The cropped image's frame on the canvas.
    public var imageFrame: CGRect

    /// - Parameter visibleContent: with auto-balance, the visibly opaque part of the crop
    ///   (relative to the crop origin), so transparent window-shadow margins don't count as
    ///   padding. `AnnotationRenderer` supplies it from `BaseImageProvider.visibleContentBounds()`.
    public init(document: AnnotationDocument, visibleContent: CGRect? = nil) {
        let size = document.imageRect.size
        guard let bg = document.background else {
            canvasSize = size
            imageFrame = CGRect(origin: .zero, size: size)
            return
        }
        let visual = (bg.autoBalance ? visibleContent : nil) ?? CGRect(origin: .zero, size: size)
        let pad = (min(max(bg.padding, 0), 0.25) * max(size.width, size.height)).rounded()
        var canvas = CGSize(width: visual.width + 2 * pad, height: visual.height + 2 * pad)
        if let ratio = bg.aspect.ratio {
            // The canvas grows to the aspect; the image never crops.
            if canvas.width / canvas.height < ratio {
                canvas.width = canvas.height * ratio
            } else {
                canvas.height = canvas.width / ratio
            }
        }
        canvas = CGSize(width: canvas.width.rounded(), height: canvas.height.rounded())

        func place(_ length: CGFloat, in total: CGFloat, leading: Bool, trailing: Bool) -> CGFloat {
            if leading { return pad }
            if trailing { return total - length - pad }
            return ((total - length) / 2).rounded()
        }
        let a = bg.alignment
        let x = place(visual.width, in: canvas.width,
                      leading: [.topLeft, .left, .bottomLeft].contains(a), trailing: [.topRight, .right, .bottomRight].contains(a))
        let y = place(visual.height, in: canvas.height,
                      leading: [.topLeft, .top, .topRight].contains(a), trailing: [.bottomLeft, .bottom, .bottomRight].contains(a))
        canvasSize = canvas
        imageFrame = CGRect(x: x - visual.minX, y: y - visual.minY, width: size.width, height: size.height)
    }

    /// Maps a point in document (base-image) space to canvas space.
    public func canvasPoint(fromDocument p: CGPoint, document: AnnotationDocument) -> CGPoint {
        CGPoint(x: p.x - document.imageRect.minX + imageFrame.minX, y: p.y - document.imageRect.minY + imageFrame.minY)
    }
}
