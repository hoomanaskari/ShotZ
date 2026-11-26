// Draws Shotz's original app icon.
// Motif: a stack of two snapshot cards (the quick-access stack) with a bold
// coral annotation arrow on the front card, on a deep indigo-to-teal tile.
// Small sizes are drawn simplified (no decoration, heavier shapes) so the
// icon reads at 16 and 32 px, as macOS icons are hinted per size.
//
// Writes both app icons: Resources/AppIcon.icns (Shotz) and
// Resources/AppIcon-Dev.icns (Shotz Dev: the same icon with an amber DEV band
// across the lower tile, so the two apps never look alike in Finder, the Dock
// or System Settings; Shotz Dev's menu-bar glyph uses the same amber).
// Usage: swift Resources/make-app-icon.swift [preview-dir]
import AppKit
import CoreText
import Foundation

let scriptDir = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
let resources = scriptDir
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// Runs `draw` in a coordinate space centred on `center`, rotated by `angle`.
func rotated(_ ctx: CGContext, center: CGPoint, angle: CGFloat, _ draw: () -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    draw()
    ctx.restoreGState()
}

/// Amber band with "DEV" (text only where it can be read), clipped by the tile.
func drawDevBand(_ ctx: CGContext, tile: CGRect, px: Int) {
    let band = CGRect(x: tile.minX, y: tile.minY + tile.height * 0.07, width: tile.width,
                      height: tile.height * (px <= 32 ? 0.22 : 0.19))
    ctx.setFillColor(color(0xFF9F0A))
    ctx.fill(band)
    guard px >= 64 else { return }
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, tile.height * 0.13, nil)!
    let text = NSAttributedString(string: "DEV", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0x1B1B1F),
        NSAttributedString.Key(kCTKernAttributeName as String): tile.height * 0.025,
    ])
    let line = CTLineCreateWithAttributedString(text)
    let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: band.midX - glyphs.width / 2 - glyphs.minX, y: band.midY - glyphs.height / 2 - glyphs.minY)
    CTLineDraw(line, ctx)
}

/// The coral arrow: a quadratic stroke with a head aligned to its end tangent.
func drawArrow(_ ctx: CGContext, from start: CGPoint, control: CGPoint, to end: CGPoint, width: CGFloat) {
    let coral = color(0xFF5A36)
    let dx = end.x - control.x, dy = end.y - control.y
    let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
    let ux = dx / len, uy = dy / len
    let head = width * 2.9
    // Stop the shaft inside the head so the joint is clean.
    let shaftEnd = CGPoint(x: end.x - ux * head * 0.55, y: end.y - uy * head * 0.55)
    ctx.setStrokeColor(coral)
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.move(to: start)
    ctx.addQuadCurve(to: shaftEnd, control: control)
    ctx.strokePath()
    let base = CGPoint(x: end.x - ux * head, y: end.y - uy * head)
    let px = -uy * head * 0.62, py = ux * head * 0.62
    ctx.move(to: end)
    ctx.addLine(to: CGPoint(x: base.x + px, y: base.y + py))
    ctx.addLine(to: CGPoint(x: base.x - px, y: base.y - py))
    ctx.closePath()
    ctx.setFillColor(coral)
    ctx.setStrokeColor(coral)
    ctx.setLineJoin(.round)
    ctx.setLineWidth(width * 0.35)
    ctx.drawPath(using: .fillStroke)
}

func render(_ px: Int, dev: Bool = false) -> Data {
    let s = CGFloat(px)
    let small = px <= 32
    let tiny = px <= 16
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 tile, ~185/1024 corner radius (use more of the
    // canvas at tiny sizes, where the margin would only cost legibility).
    let inset = tiny ? s * 0.06 : s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

    if !small {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: color(0x000000, 0.35))
        ctx.addPath(tilePath)
        ctx.setFillColor(color(0x1E2A70))
        ctx.fillPath()
        ctx.restoreGState()
    }

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb, colors: [color(0x2A2F86), color(0x1E5E96), color(0x10A79B)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    if !small {
        let glow = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.20), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
        let c = CGPoint(x: tile.minX + tile.width * 0.25, y: tile.maxY - tile.height * 0.18)
        ctx.drawRadialGradient(glow, startCenter: c, startRadius: 0, endCenter: c, endRadius: tile.width * 0.75, options: [])
    }

    let w = tile.width
    let cardSize = CGSize(width: w * (small ? 0.70 : 0.64), height: w * (small ? 0.50 : 0.45))
    let r = w * (small ? 0.08 : 0.065)

    // Back card: brighter at small sizes so the stack still reads; dropped at 16 px.
    if !tiny {
        rotated(ctx, center: CGPoint(x: tile.midX + w * 0.08, y: tile.midY + w * 0.12), angle: 0.12) {
            ctx.addPath(CGPath(roundedRect: CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2,
                                                   width: cardSize.width, height: cardSize.height),
                               cornerWidth: r, cornerHeight: r, transform: nil))
            ctx.setFillColor(color(0xFFFFFF, small ? 0.55 : 0.40))
            ctx.fillPath()
        }
    }

    // Front card.
    let frontCenter = CGPoint(x: tile.midX - w * (tiny ? 0 : 0.04), y: tile.midY - w * (tiny ? 0.02 : 0.06))
    rotated(ctx, center: frontCenter, angle: tiny ? 0 : -0.07) {
        let rect = CGRect(x: -cardSize.width / 2, y: -cardSize.height / 2, width: cardSize.width, height: cardSize.height)
        ctx.saveGState()
        if !small {
            ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.018), blur: w * 0.055, color: color(0x0A1440, 0.45))
        }
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        if !small {
            // Image well with a soft sky gradient and one abstract content bar.
            let well = rect.insetBy(dx: w * 0.032, dy: w * 0.032)
            let wr = r * 0.55
            ctx.saveGState()
            ctx.addPath(CGPath(roundedRect: well, cornerWidth: wr, cornerHeight: wr, transform: nil))
            ctx.clip()
            let sky = CGGradient(colorsSpace: srgb, colors: [color(0xE3EEF7), color(0xC9DDEC)] as CFArray, locations: [0, 1])!
            ctx.drawLinearGradient(sky, start: CGPoint(x: well.midX, y: well.maxY), end: CGPoint(x: well.midX, y: well.minY), options: [])
            ctx.setFillColor(color(0xA9C5DA))
            let bar = CGRect(x: well.minX + well.width * 0.1, y: well.maxY - well.height * 0.3,
                             width: well.width * 0.5, height: well.height * 0.11)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
            ctx.fillPath()
            ctx.restoreGState()
        }

        // The annotation: sweeps in from the lower right and points at the centre-left.
        let start = CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.16)
        let end = CGPoint(x: rect.minX + rect.width * (small ? 0.30 : 0.33), y: rect.minY + rect.height * 0.56)
        let control = CGPoint(x: rect.minX + rect.width * 0.80, y: rect.minY + rect.height * 0.70)
        drawArrow(ctx, from: start, control: control, to: end, width: w * (tiny ? 0.085 : small ? 0.07 : 0.05))
    }

    if dev { drawDevBand(ctx, tile: tile, px: px) }
    ctx.restoreGState()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

func writeIcns(dev: Bool, to output: URL) throws {
    let iconset = FileManager.default.temporaryDirectory.appending(path: "Shotz-\(UUID().uuidString).iconset")
    try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: iconset) }
    for base in [16, 32, 128, 256, 512] {
        try render(base, dev: dev).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
        try render(base * 2, dev: dev).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
    }
    let p = Process()
    p.executableURL = URL(filePath: "/usr/bin/iconutil")
    p.arguments = ["-c", "icns", iconset.path, "-o", output.path]
    try p.run()
    p.waitUntilExit()
    guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
    print("Wrote \(output.path)")
}

if CommandLine.arguments.count > 1 {
    let dir = URL(filePath: CommandLine.arguments[1], directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for px in [1024, 64, 32, 16] {
        try render(px).write(to: dir.appending(path: "AppIcon-\(px).png"))
        try render(px, dev: true).write(to: dir.appending(path: "AppIcon-Dev-\(px).png"))
    }
}
try writeIcns(dev: false, to: resources.appending(path: "AppIcon.icns"))
try writeIcns(dev: true, to: resources.appending(path: "AppIcon-Dev.icns"))
