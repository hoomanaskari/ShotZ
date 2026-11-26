import CoreGraphics
import CoreImage

/// Pixelate and blur of a base-image region. Works only on the base image, so other
/// annotations can never leak into (or be hidden by) a redaction.
enum Redactor {
    // CIContext is thread-safe (and Sendable); one shared instance avoids re-creating GPU state.
    static let ciContext = CIContext(options: [.cacheIntermediates: false, .name: "Shotz.Redactor"])

    /// Pixelate cell edge in pixels: the larger of a scale-based size (≈34 px on a 2× capture at
    /// the default strength 0.6) and a fraction of the rect's short side (≈46 % at default, capped
    /// at 48 pt), so a rect drawn tightly around a line of text gets cells of at least about half
    /// the text height and glyph shapes cannot be recovered.
    static func blockSize(strength: CGFloat, scale: CGFloat, rect: CGRect) -> CGFloat {
        let s = min(max(strength, 0), 1), k = max(scale, 1)
        let byScale = k * (5 + 20 * s)
        let byRect = min(min(rect.width, rect.height) * (0.22 + 0.4 * s), k * 48)
        return max(byScale, byRect, 4).rounded()
    }

    /// Gaussian sigma in pixels: scale-based (≈26 px on 2× at default) or ≈35 % of the rect's
    /// short side (capped at 40 pt), whichever is larger.
    static func blurRadius(strength: CGFloat, scale: CGFloat, rect: CGRect) -> CGFloat {
        let s = min(max(strength, 0), 1), k = max(scale, 1)
        let byScale = k * (3 + 17 * s)
        let byRect = min(min(rect.width, rect.height) * (0.15 + 0.33 * s), k * 40)
        return max(byScale, byRect)
    }

    /// `rect` must be integral and inside the image.
    static func pixelate(_ image: CGImage, rect: CGRect, block: CGFloat) -> CGImage? {
        guard let crop = image.cropping(to: rect) else { return nil }
        let w = Int(rect.width), h = Int(rect.height)
        let cols = max(Int((rect.width / block).rounded(.up)), 1)
        let rows = max(Int((rect.height / block).rounded(.up)), 1)
        let space = workingSpace(of: image)
        // Average each block: draw the crop into a cols × rows bitmap, exactly covering
        // cols*block × rows*block (the last row/column may extend past the crop; clamp by
        // stretching the crop to the covered area's proportion).
        guard let small = bitmap(width: cols, height: rows, space: space) else { return nil }
        small.interpolationQuality = .high
        let coveredW = CGFloat(cols) * block, coveredH = CGFloat(rows) * block
        let sx = CGFloat(cols) * rect.width / coveredW, sy = CGFloat(rows) * rect.height / coveredH
        // Fill first with an edge-ish average so partial edge blocks don't go transparent.
        small.draw(crop, in: CGRect(x: 0, y: 0, width: CGFloat(cols), height: CGFloat(rows)))
        small.draw(crop, in: CGRect(x: 0, y: CGFloat(rows) - sy, width: sx, height: sy))
        guard let tiny = small.makeImage(), let out = bitmap(width: w, height: h, space: space) else { return nil }
        out.interpolationQuality = .none
        out.draw(tiny, in: CGRect(x: 0, y: CGFloat(h) - coveredH, width: coveredW, height: coveredH))
        return out.makeImage()
    }

    /// Downsample → gaussian → upsample. The downsample is lossy, which also defeats deconvolution.
    static func blur(_ image: CGImage, rect: CGRect, radius: CGFloat) -> CGImage? {
        let bounds = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let margin = (radius * 3).rounded(.up)
        let source = rect.insetBy(dx: -margin, dy: -margin).intersection(bounds).integral
        guard let crop = image.cropping(to: source) else { return nil }
        let factor: CGFloat = radius > 12 ? 0.25 : 0.5
        var ci = CIImage(cgImage: crop).clampedToExtent()
        ci = ci.transformed(by: CGAffineTransform(scaleX: factor, y: factor), highQualityDownsample: true)
        ci = ci.applyingGaussianBlur(sigma: radius * factor)
        ci = ci.transformed(by: CGAffineTransform(scaleX: 1 / factor, y: 1 / factor))
        // CI is bottom-left origin within `crop`; the wanted rect relative to the crop:
        let localX = rect.minX - source.minX
        let localYTop = rect.minY - source.minY
        let localY = source.height - localYTop - rect.height
        let wanted = CGRect(x: localX, y: localY, width: rect.width, height: rect.height)
        let space = workingSpace(of: image)
        return ciContext.createCGImage(ci, from: wanted, format: .RGBA8, colorSpace: space)
    }

    static func workingSpace(of image: CGImage) -> CGColorSpace {
        if let s = image.colorSpace, s.model == .rgb, s.supportsOutput { return s }
        return CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    }

    static func bitmap(width: Int, height: Int, space: CGColorSpace) -> CGContext? {
        CGContext(data: nil, width: max(width, 1), height: max(height, 1), bitsPerComponent: 8, bytesPerRow: 0, space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
    }
}
