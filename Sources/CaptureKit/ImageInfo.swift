import CoreGraphics
import Foundation
import ImageIO

/// Pixel size, scale and alpha read from an image header without decoding
/// the full image.
struct ImageInfo: Equatable {
    let pixelSize: CGSize
    let scale: CGFloat
    let hasAlpha: Bool

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        else { return nil }
        self.init(properties: props)
    }

    init?(properties props: [CFString: Any]) {
        guard let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int, w > 0, h > 0
        else { return nil }
        pixelSize = CGSize(width: w, height: h)
        let dpi = (props[kCGImagePropertyDPIWidth] as? Double) ?? 72
        scale = max(1, CGFloat(dpi / 72).rounded())
        hasAlpha = (props[kCGImagePropertyHasAlpha] as? Bool) ?? false
    }

    /// True when all four corners are (nearly) transparent, the signature of
    /// a window capture (rounded corners, with or without the shadow margin).
    /// An image that merely has an alpha channel but is opaque (an area or
    /// screen capture) answers false. Reads a ≤64 px thumbnail only.
    static func cornersAreTransparent(url: URL) -> Bool {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return false }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 64,
        ]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary) else { return false }
        return cornersAreTransparent(thumb)
    }

    static func cornersAreTransparent(_ image: CGImage) -> Bool {
        let w = image.width, h = image.height
        guard w > 1, h > 1,
              let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data
        else { return false }
        ctx.clear(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        let corners = [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1)]
        return corners.allSatisfy { x, y in bytes[(y * w + x) * 4 + 3] < 64 }
    }
}
