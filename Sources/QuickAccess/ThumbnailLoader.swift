import CoreGraphics
import Foundation
import ImageIO

/// Downsamples a capture once, off the main thread, to the card's size in
/// device pixels (ARCHITECTURE §4). The full image is never decoded into memory
/// at full size by the stack.
enum ThumbnailLoader {
    /// Longest side in pixels for an image of `pixelSize` aspect-fit in `cardSize` at `scale`.
    static func maxPixelSize(pixelSize: CGSize, cardSize: CGSize, scale: CGFloat) -> Int {
        guard pixelSize.width > 0, pixelSize.height > 0 else { return Int(cardSize.width * scale) }
        let s = min(cardSize.width / pixelSize.width, cardSize.height / pixelSize.height)
        let fitted = max(pixelSize.width, pixelSize.height) * s * scale
        // Never upsample past the source.
        return max(1, Int(min(fitted, max(pixelSize.width, pixelSize.height)).rounded(.up)))
    }

    static func load(url: URL, maxPixelSize: Int) async -> CGImage? {
        await Task.detached(priority: .userInitiated) {
            make(url: url, maxPixelSize: maxPixelSize)
        }.value
    }

    static func make(url: URL, maxPixelSize: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}

import CoreImage

extension ThumbnailLoader {
    /// Fraction of the card an aspect-fit image covers (1 = fills it).
    static func coverage(pixelSize: CGSize, cardSize: CGSize) -> CGFloat {
        guard pixelSize.width > 0, pixelSize.height > 0, cardSize.width > 0, cardSize.height > 0 else { return 1 }
        let image = pixelSize.width / pixelSize.height, card = cardSize.width / cardSize.height
        return min(image / card, card / image)
    }

    /// Below this coverage the letterbox gets a blurred backdrop.
    static let backdropThreshold: CGFloat = 0.97

    /// A small, heavily blurred aspect-fill of `thumbnail` for the card's
    /// empty letterbox area. Computed once, off the main thread.
    static func backdrop(from thumbnail: CGImage, cardSize: CGSize) async -> CGImage? {
        await Task.detached(priority: .utility) {
            makeBackdrop(from: thumbnail, cardSize: cardSize)
        }.value
    }

    static func makeBackdrop(from thumbnail: CGImage, cardSize: CGSize) -> CGImage? {
        // Low resolution is fine: it is blurred far past any detail.
        let target = CGSize(width: (cardSize.width / 2).rounded(), height: (cardSize.height / 2).rounded())
        guard target.width > 0, target.height > 0, thumbnail.width > 0, thumbnail.height > 0 else { return nil }
        let input = CIImage(cgImage: thumbnail)
        let scale = max(target.width / input.extent.width, target.height / input.extent.height)
        let scaled = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let origin = CGPoint(x: (scaled.extent.width - target.width) / 2, y: (scaled.extent.height - target.height) / 2)
        let crop = CGRect(origin: origin, size: target)
        let blurred = scaled.clampedToExtent()
            .applyingGaussianBlur(sigma: 9)
            .applyingFilter("CIColorControls", parameters: [kCIInputSaturationKey: 1.15])
            .cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -origin.x, y: -origin.y))
        let context = CIContext(options: [.cacheIntermediates: false, .useSoftwareRenderer: false])
        return context.createCGImage(blurred, from: CGRect(origin: .zero, size: target))
    }
}
