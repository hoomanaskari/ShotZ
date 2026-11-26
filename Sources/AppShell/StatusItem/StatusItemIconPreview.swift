import AppKit
import ShotzCore

/// For `--debug-snapshot-ui`: the menu-bar glyph rendered off screen (test runs never
/// create the status item), on a light and a dark menu-bar strip, as macOS draws it:
/// production as a template (black on light, white on dark), ShotZ Dev in its own amber.
public enum StatusItemIconPreview {
    public static func png(variant: AppVariant, scale: CGFloat) -> Data? {
        let glyph = StatusItemIcon.make(variant: variant)
        let cell = NSSize(width: 44, height: 24)   // one menu-bar slot, in points
        let size = NSSize(width: cell.width * 2, height: cell.height)
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                   colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0)
        guard let rep else { return nil }
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let strips: [(background: NSColor, ink: NSColor)] = [
            (NSColor(white: 0.93, alpha: 1), .black),
            (NSColor(white: 0.16, alpha: 1), .white),
        ]
        for (i, strip) in strips.enumerated() {
            let slot = NSRect(x: CGFloat(i) * cell.width, y: 0, width: cell.width, height: cell.height)
            strip.background.setFill()
            slot.fill()
            let rect = NSRect(x: slot.midX - glyph.size.width / 2, y: slot.midY - glyph.size.height / 2,
                              width: glyph.size.width, height: glyph.size.height)
            draw(glyph, in: rect, ink: glyph.isTemplate ? strip.ink : nil)
        }
        return rep.representation(using: .png, properties: [:])
    }

    /// `status-item.png`: one row per app (ShotZ, then ShotZ Dev), each with the 1x and
    /// the 2x strip at their real pixel sizes.
    public static func overviewPNG() -> Data? {
        let rows = AppVariant.allCases.map { variant in
            [1.0, 2.0].compactMap { png(variant: variant, scale: $0).flatMap(cgImage) }
        }
        guard rows.allSatisfy({ $0.count == 2 }) else { return nil }
        let gap = 8
        let width = rows[0].reduce(gap) { $0 + $1.width + gap }
        let height = rows.reduce(gap) { $0 + ($1.map(\.height).max() ?? 0) + gap }
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = gap
        for row in rows {
            let rowHeight = row.map(\.height).max() ?? 0
            var x = gap
            for image in row {
                ctx.draw(image, in: CGRect(x: x, y: height - top - image.height, width: image.width, height: image.height))
                x += image.width + gap
            }
            top += rowHeight + gap
        }
        guard let image = ctx.makeImage() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    private static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Draws `image`; a template is filled with `ink` the way the menu bar tints it.
    private static func draw(_ image: NSImage, in rect: NSRect, ink: NSColor?) {
        guard let ink else {
            image.draw(in: rect)
            return
        }
        let tinted = NSImage(size: rect.size, flipped: false) { bounds in
            image.draw(in: bounds)
            ink.setFill()
            bounds.fill(using: .sourceIn)
            return true
        }
        tinted.draw(in: rect)
    }
}
