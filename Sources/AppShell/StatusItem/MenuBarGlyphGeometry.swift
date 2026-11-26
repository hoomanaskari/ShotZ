import AppKit
import CoreGraphics

/// The drawn menu-bar glyph: "corners + lens" (option C from
/// `scripts/menubar-glyph-options.swift`, chosen by the owner): four rounded
/// capture corners around a lens ring, with a lens dot when there is room.
///
/// Geometry is on ShotzIcon's 256-unit grid (y down) with its stroke language
/// (round caps and joins). Each backing scale gets its own bitmap so strokes
/// land on whole device pixels at the status item's point size.
enum MenuBarGlyphGeometry {
    /// Stroke width in device pixels at the menu-bar point size and scale
    /// (menu-bar weight, about 1.5 pt).
    static func strokePixels(pointSize: Int, scale: Int) -> Int {
        switch (pointSize, scale) {
        case (...16, 1): 1
        case (...16, _): 3
        case (...18, 1): 2
        case (...18, _): 3
        case (_, 1): 2
        default: 4
        }
    }

    /// Small renders (16 pt, or 18 pt at 1x) drop the lens dot and tighten the ring.
    static func isSimplified(pointSize: Int, scale: Int) -> Bool {
        pointSize <= 16 || (pointSize <= 18 && scale == 1)
    }

    // Design values on the 256 grid.
    static let cornerInset: CGFloat = 20
    static let cornerArm: CGFloat = 64
    static let cornerRadius: CGFloat = 26
    static let center = CGPoint(x: 128, y: 128)
    static func ringRadius(simplified: Bool) -> CGFloat { simplified ? 50 : 52 }
    static let dotRadius: CGFloat = 15

    /// One pixel-snapped bitmap of the glyph in `ink`, `pointSize` pt at `scale`.
    static func bitmap(pointSize: Int, scale: Int, ink: CGColor) -> NSBitmapImageRep? {
        let px = pointSize * scale
        guard let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(px)) // y-down pixel space, like the design grid
        ctx.scaleBy(x: 1, y: -1)
        ctx.setStrokeColor(ink)
        ctx.setFillColor(ink)
        let w = CGFloat(strokePixels(pointSize: pointSize, scale: scale))
        let k = CGFloat(px) / 256
        // Odd stroke widths centre on half pixels, even ones on whole pixels.
        let off: CGFloat = Int(w) % 2 == 1 ? 0.5 : 0
        func snap(_ v: CGFloat) -> CGFloat { (v * k - off).rounded() + off }
        ctx.setLineWidth(w)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        // Four corner brackets.
        let a = cornerInset, b = 256 - cornerInset
        for (corner, dx, dy) in [(CGPoint(x: a, y: a), 1.0, 1.0), (CGPoint(x: b, y: a), -1.0, 1.0),
                                 (CGPoint(x: a, y: b), 1.0, -1.0), (CGPoint(x: b, y: b), -1.0, -1.0)] {
            let start = CGPoint(x: snap(corner.x), y: snap(corner.y + dy * cornerArm))
            let elbow = CGPoint(x: snap(corner.x), y: snap(corner.y))
            let end = CGPoint(x: snap(corner.x + dx * cornerArm), y: snap(corner.y))
            let path = CGMutablePath()
            path.move(to: start)
            path.addArc(tangent1End: elbow, tangent2End: end, radius: cornerRadius * k)
            path.addLine(to: end)
            ctx.addPath(path)
            ctx.strokePath()
        }

        // Lens ring (centre and radius snapped so both sides land on the pixel grid).
        let simplified = isSimplified(pointSize: pointSize, scale: scale)
        let c = CGPoint(x: snap(center.x), y: snap(center.y))
        let r = (ringRadius(simplified: simplified) * k).rounded()
        ctx.strokeEllipse(in: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))

        // Lens dot.
        if !simplified {
            let dc = CGPoint(x: (center.x * k * 2).rounded() / 2, y: (center.y * k * 2).rounded() / 2)
            let dr = max(dotRadius * k, w * 0.75)
            ctx.fillEllipse(in: CGRect(x: dc.x - dr, y: dc.y - dr, width: 2 * dr, height: 2 * dr))
        }

        guard let image = ctx.makeImage() else { return nil }
        let rep = NSBitmapImageRep(cgImage: image)
        rep.size = NSSize(width: pointSize, height: pointSize)
        return rep
    }

    /// The glyph as an image with a pixel-snapped bitmap per backing scale (1x, 2x).
    static func image(pointSize: Int, ink: CGColor) -> NSImage {
        let image = NSImage(size: NSSize(width: pointSize, height: pointSize))
        for scale in [1, 2] {
            if let rep = bitmap(pointSize: pointSize, scale: scale, ink: ink) { image.addRepresentation(rep) }
        }
        return image
    }
}
