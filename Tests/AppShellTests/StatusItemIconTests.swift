import AppKit
@testable import AppShell
import ShotzCore
import Testing

/// The menu-bar glyph, whether drawn in code or supplied through scripts/make-icons.sh --glyph.
@MainActor
struct StatusItemIconTests {
    private func inkedPixels(_ image: NSImage) -> Int {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = NSSize(width: 18, height: 18)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        var count = 0
        for y in 0..<36 { for x in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { count += 1 } }
        return count
    }

    @Test func productionGlyphIsAnInked18ptTemplate() {
        let image = StatusItemIcon.make(variant: .production)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(image.isTemplate)
        #expect(image.accessibilityDescription == AppVariant.production.displayName)
        #expect(inkedPixels(image) > 20)
    }

    @Test func devGlyphIsTintedNotTemplate() {
        let image = StatusItemIcon.make(variant: .development)
        #expect(image.size == NSSize(width: 18, height: 18))
        #expect(!image.isTemplate)
        #expect(inkedPixels(image) > 20)
    }

    @Test func suppliedGlyphMatchesTheGeneratedFile() {
        // nil until scripts/make-icons.sh --glyph has generated MenuBarGlyph.generated.swift.
        #expect((StatusItemIcon.suppliedGlyph() != nil) == (MenuBarGlyphArt.png1x != nil))
    }
}
