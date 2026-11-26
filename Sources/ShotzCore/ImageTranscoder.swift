import CoreGraphics
import Foundation
import ImageIO

/// Converts a source image file into an export file (format, quality, scale).
enum ImageTranscoder {
    /// Writes `source` to `destination` as `config.format`. A PNG source with
    /// PNG output at native scale is copied byte-for-byte.
    static func write(source: URL, to destination: URL, config: ExportConfiguration) throws {
        let fm = FileManager.default
        let downscale = config.retinaScale == .downscaleTo1x ? sourceScale(source) : 1
        if config.format == .png, downscale <= 1, source.pathExtension.lowercased() == "png" {
            try fm.copyItem(at: source, to: destination)
            return
        }
        guard let src = CGImageSourceCreateWithURL(source as CFURL, nil),
              let image = decode(src, downscale: downscale)
        else { throw ExportError.unreadableImage(source.lastPathComponent) }

        guard let dest = CGImageDestinationCreateWithURL(
            destination as CFURL, config.format.utType.identifier as CFString, 1, nil
        ) else { throw ExportError.encodingFailed(config.format.rawValue) }
        var props: [CFString: Any] = [:]
        if config.format != .png {
            props[kCGImageDestinationLossyCompressionQuality] = config.quality
        }
        if downscale <= 1, let srcProps = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
            props[kCGImagePropertyDPIWidth] = srcProps[kCGImagePropertyDPIWidth]
            props[kCGImagePropertyDPIHeight] = srcProps[kCGImagePropertyDPIHeight]
        }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportError.encodingFailed(config.format.rawValue) }
    }

    /// Pixel density relative to 72 dpi (2 for Retina screenshots).
    static func sourceScale(_ url: URL) -> CGFloat {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let dpi = props[kCGImagePropertyDPIWidth] as? Double, dpi > 72
        else { return 1 }
        return CGFloat(dpi / 72).rounded()
    }

    private static func decode(_ src: CGImageSource, downscale: CGFloat) -> CGImage? {
        guard downscale > 1 else { return CGImageSourceCreateImageAtIndex(src, 0, nil) }
        guard let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int,
              let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        let maxSide = (CGFloat(max(w, h)) / downscale).rounded()
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxSide,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary)
    }
}
