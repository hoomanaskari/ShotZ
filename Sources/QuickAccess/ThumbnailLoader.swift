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
