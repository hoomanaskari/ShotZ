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
