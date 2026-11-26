import CoreGraphics
import Foundation
import ImageIO

/// Pixel size, scale and alpha read from an image header without decoding pixels.
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
}
