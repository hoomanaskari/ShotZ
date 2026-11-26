// Draws three original app-icon concepts for ShotZ (plus DEV variants) and lays
// them out on one review sheet at 1024, 128, 32 and 16 px on light and dark
// backgrounds. Exploration only: the shipping icon stays make-app-icon.swift
// until the owner picks a concept.
// Usage: swift Resources/icon-concepts.swift <out.png>
import AppKit
import CoreText
import Foundation

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
func color(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}
let coral = color(0xFF5A36)

struct Tile {
    let rect: CGRect
    let path: CGPath
    var w: CGFloat { rect.width }
}

func makeTile(_ s: CGFloat, px: Int) -> Tile {
    let inset = px <= 16 ? s * 0.06 : s * 100 / 1024
    let r = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    return Tile(rect: r, path: CGPath(roundedRect: r, cornerWidth: r.width * 0.225, cornerHeight: r.width * 0.225, transform: nil))
}

func fillTile(_ ctx: CGContext, _ t: Tile, _ colors: [UInt32], px: Int) {
    if px > 32 {
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -t.w * 0.015), blur: t.w * 0.04, color: color(0, 0.35))
        ctx.addPath(t.path); ctx.setFillColor(color(colors[0])); ctx.fillPath()
        ctx.restoreGState()
    }
    ctx.addPath(t.path); ctx.clip()
    let g = CGGradient(colorsSpace: srgb, colors: colors.map { color($0) } as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: CGPoint(x: t.rect.minX, y: t.rect.maxY), end: CGPoint(x: t.rect.maxX, y: t.rect.minY), options: [])
}

func devBand(_ ctx: CGContext, _ t: Tile, px: Int) {
    let band = CGRect(x: t.rect.minX, y: t.rect.minY + t.w * 0.07, width: t.w, height: t.w * (px <= 32 ? 0.22 : 0.19))
    ctx.setFillColor(color(0xFF9F0A)); ctx.fill(band)
    guard px >= 64 else { return }
    let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, t.w * 0.13, nil)!
    let str = NSAttributedString(string: "DEV", attributes: [
        NSAttributedString.Key(kCTFontAttributeName as String): font,
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): color(0x1B1B1F),
        NSAttributedString.Key(kCTKernAttributeName as String): t.w * 0.025])
    let line = CTLineCreateWithAttributedString(str)
    let b = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
    ctx.textPosition = CGPoint(x: band.midX - b.width / 2 - b.minX, y: band.midY - b.height / 2 - b.minY)
    CTLineDraw(line, ctx)
}

/// Slim arrow: shaft width `w`, head length 3.4w, head half-width 1.6w, slightly swept back.
func slimArrow(_ ctx: CGContext, from a: CGPoint, control c: CGPoint, to tip: CGPoint, width w: CGFloat, color col: CGColor) {
    let dx = tip.x - c.x, dy = tip.y - c.y
    let len = max((dx * dx + dy * dy).squareRoot(), 0.001)
    let ux = dx / len, uy = dy / len
    let headLen = w * 3.4, half = w * 1.6
    let base = CGPoint(x: tip.x - ux * headLen, y: tip.y - uy * headLen)
    ctx.setStrokeColor(col); ctx.setLineWidth(w); ctx.setLineCap(.round)
    ctx.move(to: a); ctx.addQuadCurve(to: CGPoint(x: base.x + ux * w * 0.4, y: base.y + uy * w * 0.4), control: c); ctx.strokePath()
    let px = -uy * half, py = ux * half
    let notch = CGPoint(x: tip.x - ux * headLen * 0.78, y: tip.y - uy * headLen * 0.78)
    ctx.move(to: tip)
    ctx.addLine(to: CGPoint(x: base.x + px, y: base.y + py))
    ctx.addLine(to: notch)
    ctx.addLine(to: CGPoint(x: base.x - px, y: base.y - py))
    ctx.closePath(); ctx.setFillColor(col); ctx.fillPath()
}

// MARK: Concept A: annotated card

func conceptA(_ ctx: CGContext, _ s: CGFloat, px: Int, dev: Bool) {
    let t = makeTile(s, px: px)
    ctx.saveGState()
    fillTile(ctx, t, [0x2A2F86, 0x1E5E96, 0x10A79B], px: px)
    let w = t.w, small = px <= 32
    let card = CGRect(x: t.rect.midX - w * 0.33, y: t.rect.midY - w * 0.25, width: w * 0.66, height: w * 0.48)
    if !small {
        let back = card.offsetBy(dx: w * 0.06, dy: w * 0.07)
        ctx.addPath(CGPath(roundedRect: back, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
        ctx.setFillColor(color(0xFFFFFF, 0.35)); ctx.fillPath()
    }
    ctx.saveGState()
    if !small { ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.02), blur: w * 0.05, color: color(0x0A1440, 0.45)) }
    ctx.addPath(CGPath(roundedRect: card, cornerWidth: w * 0.06, cornerHeight: w * 0.06, transform: nil))
    ctx.setFillColor(color(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    let well = card.insetBy(dx: w * (small ? 0.05 : 0.035), dy: w * (small ? 0.05 : 0.035))
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: well, cornerWidth: w * 0.035, cornerHeight: w * 0.035, transform: nil)); ctx.clip()
    let sky = CGGradient(colorsSpace: srgb, colors: [color(0xDCEAF6), color(0xBCD5EA)] as CFArray, locations: nil)!
    ctx.drawLinearGradient(sky, start: CGPoint(x: well.midX, y: well.maxY), end: CGPoint(x: well.midX, y: well.minY), options: [])
    if !small {
        // A soft abstract hill: "a screenshot", not a document.
        ctx.move(to: CGPoint(x: well.minX, y: well.minY + well.height * 0.25))
        ctx.addQuadCurve(to: CGPoint(x: well.maxX, y: well.minY + well.height * 0.18), control: CGPoint(x: well.midX, y: well.minY + well.height * 0.55))
        ctx.addLine(to: CGPoint(x: well.maxX, y: well.minY)); ctx.addLine(to: CGPoint(x: well.minX, y: well.minY)); ctx.closePath()
        ctx.setFillColor(color(0x9DBFD9)); ctx.fillPath()
    }
    ctx.restoreGState()
    // The highlighted spot and the slim arrow pointing at it.
    let spot = CGPoint(x: well.minX + well.width * 0.32, y: well.minY + well.height * 0.62)
    let ring = w * (small ? 0.10 : 0.075)
    ctx.setStrokeColor(coral); ctx.setLineWidth(w * (small ? 0.045 : 0.026))
    ctx.strokeEllipse(in: CGRect(x: spot.x - ring, y: spot.y - ring * 0.8, width: ring * 2, height: ring * 1.6))
    if px > 16 {
        let start = CGPoint(x: card.maxX + w * 0.04, y: card.minY - w * 0.03)
        slimArrow(ctx, from: start, control: CGPoint(x: well.maxX - well.width * 0.05, y: spot.y),
                  to: CGPoint(x: spot.x + ring * 1.25, y: spot.y - ring * 0.15), width: w * (small ? 0.045 : 0.03), color: coral)
    }
    if dev { devBand(ctx, t, px: px) }
    ctx.restoreGState()
}

// MARK: Concept B: crop marks

func conceptB(_ ctx: CGContext, _ s: CGFloat, px: Int, dev: Bool) {
    let t = makeTile(s, px: px)
    ctx.saveGState()
    fillTile(ctx, t, [0x2B2D3A, 0x30368A, 0x4A3FB8], px: px)
    let w = t.w, small = px <= 32
    let frame = t.rect.insetBy(dx: w * 0.19, dy: w * 0.19)
    let arm = frame.width * (small ? 0.34 : 0.28)
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(w * (small ? 0.075 : 0.05))
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    for (cx, cy, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                             (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: cx, y: cy + dy * arm)); ctx.addLine(to: CGPoint(x: cx, y: cy)); ctx.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
    }
    ctx.strokePath()
    // The captured card inside, tilted, with a coral highlight bar.
    let card = frame.insetBy(dx: frame.width * (small ? 0.2 : 0.18), dy: frame.height * (small ? 0.26 : 0.24))
    ctx.saveGState()
    ctx.translateBy(x: card.midX, y: card.midY); ctx.rotate(by: small ? 0 : -0.08)
    let local = CGRect(x: -card.width / 2, y: -card.height / 2, width: card.width, height: card.height)
    if !small { ctx.setShadow(offset: CGSize(width: 0, height: -w * 0.015), blur: w * 0.04, color: color(0, 0.4)) }
    ctx.addPath(CGPath(roundedRect: local, cornerWidth: w * 0.035, cornerHeight: w * 0.035, transform: nil))
    ctx.setFillColor(color(0xF4F6FB)); ctx.fillPath()
    ctx.setShadow(offset: .zero, blur: 0, color: nil)
    let mark = CGRect(x: local.minX + local.width * 0.16, y: local.midY - local.height * 0.12, width: local.width * 0.6, height: local.height * 0.24)
    ctx.addPath(CGPath(roundedRect: mark, cornerWidth: mark.height / 2, cornerHeight: mark.height / 2, transform: nil))
    ctx.setFillColor(color(0xFF5A36, small ? 1 : 0.85)); ctx.fillPath()
    ctx.restoreGState()
    if dev { devBand(ctx, t, px: px) }
    ctx.restoreGState()
}

// MARK: Concept C: Z in a frame

func conceptC(_ ctx: CGContext, _ s: CGFloat, px: Int, dev: Bool) {
    let t = makeTile(s, px: px)
    ctx.saveGState()
    fillTile(ctx, t, [0x15161C, 0x23263A, 0x2E3150], px: px)
    let w = t.w, small = px <= 32
    let frame = t.rect.insetBy(dx: w * 0.17, dy: w * 0.2)
    // Selection frame (dashed above 32 px, solid below).
    ctx.setStrokeColor(color(0xFFFFFF, small ? 0.9 : 0.75)); ctx.setLineWidth(w * (small ? 0.05 : 0.022))
    if !small { ctx.setLineDash(phase: 0, lengths: [w * 0.05, w * 0.035]) }
    ctx.addPath(CGPath(roundedRect: frame, cornerWidth: w * 0.04, cornerHeight: w * 0.04, transform: nil)); ctx.strokePath()
    ctx.setLineDash(phase: 0, lengths: [])
    // The Z: white top and bottom bars, coral diagonal (the annotation stroke).
    let z = frame.insetBy(dx: frame.width * 0.2, dy: frame.height * 0.2)
    let bar = w * (small ? 0.1 : 0.075)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    ctx.setStrokeColor(color(0xFFFFFF)); ctx.setLineWidth(bar)
    ctx.move(to: CGPoint(x: z.minX, y: z.maxY)); ctx.addLine(to: CGPoint(x: z.maxX, y: z.maxY))
    ctx.move(to: CGPoint(x: z.minX, y: z.minY)); ctx.addLine(to: CGPoint(x: z.maxX, y: z.minY))
    ctx.strokePath()
    ctx.setStrokeColor(coral)
    ctx.move(to: CGPoint(x: z.maxX, y: z.maxY)); ctx.addLine(to: CGPoint(x: z.minX, y: z.minY)); ctx.strokePath()
    // Corner handles on the frame, as on a live selection.
    if !small {
        ctx.setFillColor(color(0xFFFFFF))
        for p in [CGPoint(x: frame.minX, y: frame.minY), CGPoint(x: frame.maxX, y: frame.minY), CGPoint(x: frame.minX, y: frame.maxY), CGPoint(x: frame.maxX, y: frame.maxY)] {
            ctx.fillEllipse(in: CGRect(x: p.x - w * 0.025, y: p.y - w * 0.025, width: w * 0.05, height: w * 0.05))
        }
    }
    if dev { devBand(ctx, t, px: px) }
    ctx.restoreGState()
}

// MARK: Sheet

typealias Draw = (CGContext, CGFloat, Int, Bool) -> Void
func render(_ draw: Draw, px: Int, dev: Bool) -> CGImage {
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    draw(ctx, CGFloat(px), px, dev)
    return ctx.makeImage()!
}

let concepts: [(String, String, Draw)] = [
    ("A  Annotated card", "Refined current motif: slim arrow pointing at a highlighted spot.", conceptA),
    ("B  Crop marks", "Capture corners framing the captured card and its highlight.", conceptB),
    ("C  Z in a frame", "A bold Z (coral diagonal = annotation) inside a live selection.", conceptC),
]
let rowH: CGFloat = 330, colW: CGFloat = 1180, pad: CGFloat = 40
let sheetW = Int(pad * 2 + colW * 2), sheetH = Int(120 + rowH * CGFloat(concepts.count) + 40)
let ctx = CGContext(data: nil, width: sheetW, height: sheetH, bitsPerComponent: 8, bytesPerRow: 0, space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.setFillColor(color(0xFFFFFF)); ctx.fill(CGRect(x: 0, y: 0, width: sheetW, height: sheetH))

func text(_ str: String, _ size: CGFloat, _ x: CGFloat, _ yTop: CGFloat, bold: Bool = false, col: CGColor = color(0x1D1D1F)) {
    let font = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
    let a = NSAttributedString(string: str, attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font,
                                                          NSAttributedString.Key(kCTForegroundColorAttributeName as String): col])
    ctx.textPosition = CGPoint(x: x, y: CGFloat(sheetH) - yTop - size)
    CTLineDraw(CTLineCreateWithAttributedString(a), ctx)
}
func place(_ img: CGImage, _ x: CGFloat, _ yTop: CGFloat, scale: CGFloat) {
    ctx.interpolationQuality = scale > 1 ? .none : .high
    let w = CGFloat(img.width) * scale, h = CGFloat(img.height) * scale
    ctx.draw(img, in: CGRect(x: x, y: CGFloat(sheetH) - yTop - h, width: w, height: h))
}

text("ShotZ app icon concepts (pick one)", 30, pad, 30, bold: true)
text("Per background: 1024 px shown at 220 · 128 px actual · 32 px actual and ×4 · 16 px actual and ×6 · DEV variant at 128 and 32", 15, pad, 72, col: color(0x6E6E73))
for (i, c) in concepts.enumerated() {
    let top = 120 + rowH * CGFloat(i)
    for (j, dark) in [false, true].enumerated() {
        let x0 = pad + colW * CGFloat(j)
        ctx.setFillColor(dark ? color(0x1E1E20) : color(0xECECEE))
        ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: CGFloat(sheetH) - top - rowH + 20, width: colW - 20, height: rowH - 20), cornerWidth: 18, cornerHeight: 18, transform: nil))
        ctx.fillPath()
        let ink = dark ? color(0xF5F5F7) : color(0x1D1D1F)
        text(c.0 + (dark ? "  (dark)" : "  (light)"), 17, x0 + 20, top + 12, bold: true, col: ink)
        text(c.1, 12, x0 + 20, top + 36, col: dark ? color(0xA1A1A6) : color(0x6E6E73))
        let y = top + 64
        place(render(c.2, px: 1024, dev: false), x0 + 16, y, scale: 220.0 / 1024)
        place(render(c.2, px: 128, dev: false), x0 + 260, y + 46, scale: 1)
        place(render(c.2, px: 32, dev: false), x0 + 410, y + 94, scale: 1)
        place(render(c.2, px: 32, dev: false), x0 + 452, y + 46, scale: 4)
        place(render(c.2, px: 16, dev: false), x0 + 600, y + 102, scale: 1)
        place(render(c.2, px: 16, dev: false), x0 + 628, y + 62, scale: 6)
        place(render(c.2, px: 128, dev: true), x0 + 760, y + 46, scale: 1)
        place(render(c.2, px: 32, dev: true), x0 + 910, y + 94, scale: 1)
        place(render(c.2, px: 32, dev: true), x0 + 952, y + 46, scale: 4)
    }
}
let out = URL(filePath: CommandLine.arguments[1])
try NSBitmapImageRep(cgImage: ctx.makeImage()!).representation(using: .png, properties: [:])!.write(to: out)
print("Wrote \(out.path)")
