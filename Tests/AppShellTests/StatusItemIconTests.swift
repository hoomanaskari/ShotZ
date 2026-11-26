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

    // MARK: Drawn glyph ("corners + lens"), per backing scale

    private func bitmaps(_ image: NSImage) -> [Int: NSBitmapImageRep] {
        var out: [Int: NSBitmapImageRep] = [:]
        for rep in image.representations.compactMap({ $0 as? NSBitmapImageRep }) {
            out[Int((CGFloat(rep.pixelsWide) / image.size.width).rounded())] = rep
        }
        return out
    }

    private func inked(_ rep: NSBitmapImageRep) -> [NSColor] {
        var out: [NSColor] = []
        for y in 0..<rep.pixelsHigh { for x in 0..<rep.pixelsWide {
            if let c = rep.colorAt(x: x, y: y), c.alphaComponent > 0.9 { out.append(c) }
        } }
        return out
    }

    @Test func drawnGlyphHasPixelSnappedOneAndTwoXBitmaps() {
        for variant in AppVariant.allCases {
            let image = StatusItemIcon.drawn(variant: variant)
            #expect(image.size == NSSize(width: StatusItemIcon.pointSize, height: StatusItemIcon.pointSize))
            #expect(image.accessibilityDescription == variant.displayName)
            let reps = bitmaps(image)
            #expect(reps[1]?.pixelsWide == StatusItemIcon.pointSize, "1x bitmap for \(variant)")
            #expect(reps[2]?.pixelsWide == 2 * StatusItemIcon.pointSize, "2x bitmap for \(variant)")
            for (scale, rep) in reps {
                // Crisp: a good share of the inked pixels are fully opaque (strokes on whole pixels).
                #expect(inked(rep).count > 40 * scale, "\(variant) @\(scale)x has ink")
            }
        }
    }

    @Test func drawnProductionGlyphIsATemplate() {
        let image = StatusItemIcon.drawn(variant: .production)
        #expect(image.isTemplate)
        let colors = bitmaps(image).values.flatMap(inked)
        #expect(!colors.isEmpty && colors.allSatisfy { ($0.usingColorSpace(.sRGB)?.brightnessComponent ?? 1) < 0.1 })
    }

    @Test func drawnDevGlyphIsTintedAmber() {
        let image = StatusItemIcon.drawn(variant: .development)
        #expect(!image.isTemplate)
        let colors = bitmaps(image).values.flatMap(inked).compactMap { $0.usingColorSpace(.sRGB) }
        #expect(!colors.isEmpty)
        #expect(colors.allSatisfy { $0.redComponent > 0.9 && $0.greenComponent > 0.5 && $0.blueComponent < 0.2 })
    }

    @Test func simplifiedAtOneXDropsTheLensDot() {
        #expect(MenuBarGlyphGeometry.isSimplified(pointSize: 18, scale: 1))
        #expect(!MenuBarGlyphGeometry.isSimplified(pointSize: 18, scale: 2))
        #expect(MenuBarGlyphGeometry.strokePixels(pointSize: 18, scale: 2) == 3)
    }
}
