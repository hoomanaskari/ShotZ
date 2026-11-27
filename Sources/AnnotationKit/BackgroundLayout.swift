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

        // Position (the 9-way grid) splits the free margin around the image in each axis: the
        // chosen side keeps a quarter of the padding, the other side takes the rest. So with Auto
        // aspect and symmetric padding the grid still moves the image, and with a fixed aspect it
        // moves it in both axes. Centre keeps the exact earlier arithmetic (existing documents
        // render as before).
        let inset = (pad * Self.alignedMarginFraction).rounded()
        func place(_ length: CGFloat, in total: CGFloat, leading: Bool, trailing: Bool) -> CGFloat {
            let free = total - length
            if leading { return min(inset, (free / 2).rounded()) }
            if trailing { return free - min(inset, (free / 2).rounded()) }
            return (free / 2).rounded()
        }
        let a = bg.alignment
        let x = place(visual.width, in: canvas.width,
                      leading: [.topLeft, .left, .bottomLeft].contains(a), trailing: [.topRight, .right, .bottomRight].contains(a))
        let y = place(visual.height, in: canvas.height,
                      leading: [.topLeft, .top, .topRight].contains(a), trailing: [.bottomLeft, .bottom, .bottomRight].contains(a))
        canvasSize = canvas
        imageFrame = CGRect(x: x - visual.minX, y: y - visual.minY, width: size.width, height: size.height)
    }

    /// The margin the chosen side keeps, as a fraction of the padding.
    public static let alignedMarginFraction: CGFloat = 0.25

    /// Whether the position grid can move the image: there is margin around it in some axis
    /// (padding, or a fixed aspect's extra room). False with no padding and Auto aspect.
    public static func canPosition(_ document: AnnotationDocument, visibleContent: CGRect? = nil) -> Bool {
        guard let bg = document.background else { return false }
        var centred = document
        centred.background?.alignment = .center
        let layout = BackgroundLayout(document: centred, visibleContent: bg.autoBalance ? visibleContent : nil)
        let visual = (bg.autoBalance ? visibleContent : nil)?.size ?? document.imageRect.size
        return layout.canvasSize.width - visual.width >= 2 || layout.canvasSize.height - visual.height >= 2
    }

    /// Maps a point in document (base-image) space to canvas space.
    public func canvasPoint(fromDocument p: CGPoint, document: AnnotationDocument) -> CGPoint {
        CGPoint(x: p.x - document.imageRect.minX + imageFrame.minX, y: p.y - document.imageRect.minY + imageFrame.minY)
    }
}
