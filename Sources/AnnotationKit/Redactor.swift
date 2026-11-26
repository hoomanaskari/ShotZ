import Accelerate
import CoreGraphics
import CoreImage

/// Pixelate and blur of a base-image region. Works only on the base image, so other
/// annotations can never leak into (or be hidden by) a redaction.
enum Redactor {
    // CIContext is thread-safe (and Sendable); one shared instance avoids re-creating GPU state.
    static let ciContext = CIContext(options: [.cacheIntermediates: false, .name: "Shotz.Redactor"])

    /// Pixelate cell edge in pixels: the larger of a scale-based size (≈34 px on a 2× capture at
    /// the default strength 0.6) and a fraction of the rect's short side (≈71 % at default, capped
    /// at 48 pt), so a rect drawn tightly around a line of text gets cells about as tall as the
    /// text: each cell averages whole glyphs, which defeats candidate-matching attacks.
    static func blockSize(strength: CGFloat, scale: CGFloat, rect: CGRect) -> CGFloat {
        let s = min(max(strength, 0), 1), k = max(scale, 1)
        let byScale = k * (5 + 20 * s)
        let byRect = min(min(rect.width, rect.height) * (0.35 + 0.6 * s), k * 48)
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

    /// Cell grid for a rect: the rect is divided into equal cells as close as possible to `block`,
    /// so there are no partial edge cells (a thin edge strip would average fewer pixels and
    /// reveal finer detail than the interior).
    static func cellGrid(for size: CGSize, block: CGFloat) -> (cols: Int, rows: Int) {
        (max(Int((size.width / block).rounded()), 1), max(Int((size.height / block).rounded()), 1))
    }

    /// `rect` must be integral and inside the image. Each cell is the exact mean of its pixels,
    /// written fully opaque, so no original pixel can show through anywhere in the rect.
    /// Vectorised with Accelerate (fast in debug builds too): each band of rows is summed per
    /// column, each cell reduced with `vDSP_sve`, and output rows filled by pattern copies.
    static func pixelate(_ image: CGImage, rect: CGRect, block: CGFloat) -> CGImage? {
        guard let crop = image.cropping(to: rect) else { return nil }
        let w = Int(rect.width), h = Int(rect.height)
        guard w > 0, h > 0 else { return nil }
        let (cols, rows) = cellGrid(for: rect.size, block: block)
        let space = workingSpace(of: image)
        // Opaque working copy in BGRA premultiplied (transparent areas average against black).
        guard let ctx = bitmap(width: w, height: h, space: space), let data = ctx.data else { return nil }
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: w, height: h))
        let rowBytes = ctx.bytesPerRow
        let px = data.bindMemory(to: UInt8.self, capacity: rowBytes * h)
        let n = w * 4
        let rowF = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let acc = UnsafeMutablePointer<Float>.allocate(capacity: n)
        let pattern = UnsafeMutablePointer<UInt8>.allocate(capacity: n)
        defer { rowF.deallocate(); acc.deallocate(); pattern.deallocate() }
        // Cell boundaries split the rect evenly (integer pixel edges).
        let xs = (0...cols).map { $0 * w / cols }
        let ys = (0...rows).map { $0 * h / rows }
        for r in 0..<rows {
            let y0 = ys[r], y1 = ys[r + 1]
            vDSP_vclr(acc, 1, vDSP_Length(n))
            for y in y0..<y1 {
                vDSP_vfltu8(px + y * rowBytes, 1, rowF, 1, vDSP_Length(n))
                vDSP_vadd(acc, 1, rowF, 1, acc, 1, vDSP_Length(n))
            }
            for c in 0..<cols {
                let x0 = xs[c], cw = xs[c + 1] - x0
                let count = Float(cw * (y1 - y0))
                var cell: (UInt8, UInt8, UInt8, UInt8) = (0, 0, 0, 255)
                var sum: Float = 0
                vDSP_sve(acc + x0 * 4, 4, &sum, vDSP_Length(cw)); cell.0 = UInt8(min((sum / count).rounded(), 255))
                vDSP_sve(acc + x0 * 4 + 1, 4, &sum, vDSP_Length(cw)); cell.1 = UInt8(min((sum / count).rounded(), 255))
                vDSP_sve(acc + x0 * 4 + 2, 4, &sum, vDSP_Length(cw)); cell.2 = UInt8(min((sum / count).rounded(), 255))
                withUnsafeBytes(of: &cell) { memset_pattern4(pattern + x0 * 4, $0.baseAddress!, cw * 4) }
            }
            for y in y0..<y1 { memcpy(px + y * rowBytes, pattern, n) }
        }
        return ctx.makeImage()
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
