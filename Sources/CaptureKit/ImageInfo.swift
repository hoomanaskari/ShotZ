import CoreGraphics
import Foundation
import ImageIO

/// Pixel size and scale read from an image header without decoding pixels.
struct ImageInfo: Equatable {
    let pixelSize: CGSize
    let scale: CGFloat

    init?(url: URL) {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        pixelSize = CGSize(width: w, height: h)
        let dpi = props[kCGImagePropertyDPIWidth] as? Double ?? 72
        scale = max(1, CGFloat(dpi / 72).rounded())
    }
}
