// Draws Shotz's original app icon and writes Resources/AppIcon.icns.
// Motif: two stacked snapshot cards (the quick-access stack) with a coral
// annotation stroke on the front card, on a deep blue-to-teal tile.
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

func card(_ ctx: CGContext, center: CGPoint, size: CGSize, angle: CGFloat, radius: CGFloat, draw: (CGRect) -> Void) {
    ctx.saveGState()
    ctx.translateBy(x: center.x, y: center.y)
    ctx.rotate(by: angle)
    draw(CGRect(x: -size.width / 2, y: -size.height / 2, width: size.width, height: size.height))
    ctx.restoreGState()
}

/// Amber band with "DEV", clipped by the tile's rounded shape (already clipped).
func drawDevBand(_ ctx: CGContext, tile: CGRect) {
    let band = CGRect(x: tile.minX, y: tile.minY + tile.height * 0.07, width: tile.width, height: tile.height * 0.19)
    ctx.setFillColor(color(0xFF9F0A))
    ctx.fill(band)
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

func render(_ px: Int, dev: Bool = false) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // macOS icon grid: 824/1024 tile, ~185/1024 corner radius.
    let inset = s * 100 / 1024
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)

    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.035, color: color(0x000000, 0.35))
    ctx.addPath(tilePath)
    ctx.setFillColor(color(0x1B2A6B))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(tilePath)
    ctx.clip()
    let bg = CGGradient(colorsSpace: srgb, colors: [color(0x23307A), color(0x1F5F8B), color(0x14A39A)] as CFArray,
                        locations: [0, 0.55, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    // Soft light from the top-left.
    let glow = CGGradient(colorsSpace: srgb, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawRadialGradient(glow, startCenter: CGPoint(x: tile.minX + tile.width * 0.25, y: tile.maxY - tile.height * 0.2),
                           startRadius: 0, endCenter: CGPoint(x: tile.minX + tile.width * 0.25, y: tile.maxY - tile.height * 0.2),
                           endRadius: tile.width * 0.75, options: [])

    let w = tile.width
    let cardSize = CGSize(width: w * 0.62, height: w * 0.62 * 10 / 16 * 1.08)
    let r = w * 0.06

    // Back card.
    card(ctx, center: CGPoint(x: tile.midX + w * 0.07, y: tile.midY + w * 0.12), size: cardSize, angle: 0.10, radius: r) { rect in
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.35))
        ctx.fillPath()
    }

    // Front card with an image well and a coral annotation arrow.
    card(ctx, center: CGPoint(x: tile.midX - w * 0.04, y: tile.midY - w * 0.06), size: cardSize, angle: -0.06, radius: r) { rect in
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.015), blur: w * 0.05, color: color(0x0A1440, 0.45))
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil))
        ctx.setFillColor(color(0xFFFFFF))
        ctx.fillPath()
        ctx.restoreGState()

        let well = rect.insetBy(dx: w * 0.035, dy: w * 0.035)
        let wr = r * 0.6
        ctx.saveGState()
        ctx.addPath(CGPath(roundedRect: well, cornerWidth: wr, cornerHeight: wr, transform: nil))
        ctx.clip()
        let wellGradient = CGGradient(colorsSpace: srgb, colors: [color(0xDCEBF5), color(0xC4DCEC)] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(wellGradient, start: CGPoint(x: well.midX, y: well.maxY), end: CGPoint(x: well.midX, y: well.minY), options: [])
        // Two abstract "content" bars.
        ctx.setFillColor(color(0x9FBFD6))
        for (i, frac) in [0.62, 0.42].enumerated() {
            let bar = CGRect(x: well.minX + well.width * 0.1, y: well.maxY - well.height * (0.28 + 0.2 * CGFloat(i)),
                             width: well.width * frac, height: well.height * 0.09)
            ctx.addPath(CGPath(roundedRect: bar, cornerWidth: bar.height / 2, cornerHeight: bar.height / 2, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()

        // Annotation: a curved coral arrow sweeping in from the lower right.
        let coral = color(0xFF6B4A)
        let start = CGPoint(x: well.maxX - well.width * 0.08, y: well.minY + well.height * 0.14)
        let end = CGPoint(x: well.minX + well.width * 0.42, y: well.minY + well.height * 0.5)
        let control = CGPoint(x: well.minX + well.width * 0.78, y: well.minY + well.height * 0.62)
        ctx.setStrokeColor(coral)
        ctx.setLineWidth(w * 0.042)
        ctx.setLineCap(.round)
        ctx.move(to: start)
        ctx.addQuadCurve(to: end, control: control)
        ctx.strokePath()
        // Arrowhead along the tangent at `end`.
        let dx = end.x - control.x, dy = end.y - control.y
        let len = max(sqrt(dx * dx + dy * dy), 0.001)
        let ux = dx / len, uy = dy / len
        let head = w * 0.11
        let tip = CGPoint(x: end.x + ux * head * 0.45, y: end.y + uy * head * 0.45)
        let base = CGPoint(x: tip.x - ux * head, y: tip.y - uy * head)
        let px = -uy * head * 0.55, py = ux * head * 0.55
        ctx.move(to: tip)
        ctx.addLine(to: CGPoint(x: base.x + px, y: base.y + py))
        ctx.addLine(to: CGPoint(x: base.x - px, y: base.y - py))
        ctx.closePath()
        ctx.setFillColor(coral)
        ctx.setLineJoin(.round)
        ctx.setLineWidth(w * 0.012)
        ctx.drawPath(using: .fillStroke)
    }
    if dev { drawDevBand(ctx, tile: tile) }
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
