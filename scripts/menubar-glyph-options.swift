// Menu-bar glyph options for ShotZ (M5), derived from the owner's app-icon motif:
// a camera inside capture corners, with a marker stroke.
//
//   swift scripts/menubar-glyph-options.swift <output-dir>
//
// Writes a comparison sheet (`menubar-options@2x.png`: every option and the current
// glyph in mock light and dark menu bars at 16/18/22 pt, plus the DEV amber variant)
// and a pixel sheet (`menubar-pixels.png`: each glyph at 1x and 2x, enlarged).
//
// This file is DATA for the owner's choice, not wired into the app. The chosen
// option's `shapes(for:)` is meant to be ported into AppShell's StatusItemIcon.
//
// Geometry is on ShotzIcon's 256-unit grid (y down) with its stroke language:
// round caps and joins, rounded corners, one stroke weight per glyph. The weight is
// menu-bar weight (heavier than Phosphor regular, like system menu extras) and is
// chosen per size and scale so strokes land on whole device pixels.

import AppKit
import CoreGraphics

// MARK: - Shapes

enum Shape {
    case roundedRect(CGRect, radius: CGFloat)
    case circle(center: CGPoint, radius: CGFloat)
    case dot(center: CGPoint, radius: CGFloat)                 // filled
    case corner(CGPoint, dx: CGFloat, dy: CGFloat, arm: CGFloat, radius: CGFloat) // L bracket at a box corner
    case polyline([CGPoint])                                    // axis-snapped endpoints
    case curve(CGPath)                                          // free curve, not snapped
}

enum Option: String, CaseIterable {
    case framedCamera = "A  Framed camera"
    case cameraMarker = "B  Camera + marker stroke"
    case cornersLens = "C  Corners + lens"
    case camera = "D  Camera"

    /// Four L brackets at the corners of the box inset by `inset`.
    static func corners(inset i: CGFloat, arm: CGFloat, radius r: CGFloat) -> [Shape] {
        let a = i, b = 256 - i
        return [
            .corner(CGPoint(x: a, y: a), dx: 1, dy: 1, arm: arm, radius: r),
            .corner(CGPoint(x: b, y: a), dx: -1, dy: 1, arm: arm, radius: r),
            .corner(CGPoint(x: a, y: b), dx: 1, dy: -1, arm: arm, radius: r),
            .corner(CGPoint(x: b, y: b), dx: -1, dy: -1, arm: arm, radius: r),
        ]
    }

    /// The camera's top hump as an open polyline sitting on the body's top edge.
    static func hump(top y: CGFloat, height h: CGFloat, from x0: CGFloat, to x1: CGFloat, slope s: CGFloat) -> Shape {
        .polyline([CGPoint(x: x0, y: y), CGPoint(x: x0 + s, y: y - h), CGPoint(x: x1 - s, y: y - h), CGPoint(x: x1, y: y)])
    }

    /// The glyph for a point size and scale; 16 pt (and 18 pt at 1x) drop the
    /// smallest details (the camera hump, the lens dot, the squiggle's second wave).
    func shapes(for size: Int, scale: Int = 2) -> [Shape] {
        let small = size <= 16 || (size <= 18 && scale == 1)
        switch self {
        case .framedCamera:
            var s = Self.corners(inset: 12, arm: small ? 46 : 50, radius: 22)
            s.append(.roundedRect(CGRect(x: 56, y: small ? 82 : 100, width: 144, height: small ? 106 : 88), radius: 20))
            if !small { s.append(Self.hump(top: 100, height: 30, from: 98, to: 158, slope: 14)) }
            s.append(.circle(center: CGPoint(x: 128, y: small ? 135 : 144), radius: small ? 34 : 30))
            return s
        case .cameraMarker:
            var s: [Shape] = [.roundedRect(CGRect(x: 32, y: small ? 40 : 62, width: 192, height: small ? 116 : 100), radius: 26)]
            if !small { s.append(Self.hump(top: 62, height: 32, from: 82, to: 174, slope: 18)) }
            s.append(.circle(center: CGPoint(x: 128, y: small ? 98 : 112), radius: small ? 34 : 32))
            let p = CGMutablePath()
            if small {
                p.move(to: CGPoint(x: 44, y: 214))
                p.addCurve(to: CGPoint(x: 212, y: 206), control1: CGPoint(x: 100, y: 186), control2: CGPoint(x: 156, y: 236))
            } else {
                p.move(to: CGPoint(x: 40, y: 216))
                p.addCurve(to: CGPoint(x: 132, y: 212), control1: CGPoint(x: 72, y: 186), control2: CGPoint(x: 100, y: 240))
                p.addCurve(to: CGPoint(x: 216, y: 204), control1: CGPoint(x: 160, y: 186), control2: CGPoint(x: 192, y: 226))
            }
            s.append(.curve(p))
            return s
        case .cornersLens:
            var s = Self.corners(inset: 20, arm: 64, radius: 26)
            s.append(.circle(center: CGPoint(x: 128, y: 128), radius: small ? 50 : 52))
            if !small { s.append(.dot(center: CGPoint(x: 128, y: 128), radius: 15)) }
            return s
        case .camera:
            var s: [Shape] = [.roundedRect(CGRect(x: 24, y: small ? 64 : 78, width: 208, height: small ? 140 : 126), radius: 30)]
            if !small { s.append(Self.hump(top: 78, height: 30, from: 82, to: 174, slope: 18)) }
            s.append(.circle(center: CGPoint(x: 128, y: small ? 134 : 141), radius: small ? 42 : 42))
            if size >= 22 { s.append(.dot(center: CGPoint(x: 196, y: 108), radius: 9)) }
            return s
        }
    }
}

/// Stroke width in device pixels for (point size, scale): menu-bar weight
/// (about 1.25–1.75 pt), always a whole number of pixels.
func strokePixels(size: Int, scale: Int) -> Int {
    switch (size, scale) {
    case (16, 1): 1
    case (16, _): 3
    case (18, 1): 2
    case (18, _): 3
    case (22, 1): 2
    default: 4
    }
}

// MARK: - Rendering one glyph (pixel-snapped)

/// Renders `option` (or the current glyph when nil) at `size` pt × `scale` as a
/// template mask: white glyph, transparent background.
func renderGlyph(_ option: Option?, size: Int, scale: Int) -> CGImage {
    let px = size * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // y-down pixel space.
    ctx.translateBy(x: 0, y: CGFloat(px))
    ctx.scaleBy(x: 1, y: -1)
    ctx.setFillColor(.white)
    ctx.setStrokeColor(.white)
    guard let option else {
        drawCurrentGlyph(ctx, size: CGFloat(size), scale: CGFloat(scale))
        return ctx.makeImage()!
    }
    let w = CGFloat(strokePixels(size: size, scale: scale))
    let k = CGFloat(px) / 256
    let off: CGFloat = Int(w) % 2 == 1 ? 0.5 : 0
    func snap(_ v: CGFloat) -> CGFloat { (v * k - off).rounded() + off }
    func pt(_ p: CGPoint) -> CGPoint { CGPoint(x: snap(p.x), y: snap(p.y)) }
    ctx.setLineWidth(w)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for shape in option.shapes(for: size, scale: scale) {
        switch shape {
        case .roundedRect(let r, let radius):
            let x0 = snap(r.minX), x1 = snap(r.maxX), y0 = snap(r.minY), y1 = snap(r.maxY)
            let rr = min(radius * k, (x1 - x0) / 2, (y1 - y0) / 2)
            ctx.addPath(CGPath(roundedRect: CGRect(x: x0, y: y0, width: x1 - x0, height: y1 - y0), cornerWidth: rr, cornerHeight: rr, transform: nil))
            ctx.strokePath()
        case .circle(let c, let r):
            let center = pt(c)
            let radius = (r * k).rounded()
            ctx.addEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
            ctx.strokePath()
        case .dot(let c, let r):
            let center = CGPoint(x: (c.x * k * 2).rounded() / 2, y: (c.y * k * 2).rounded() / 2)
            let radius = max(r * k, w * 0.75)
            ctx.fillEllipse(in: CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius))
        case .corner(let o, let dx, let dy, let arm, let radius):
            let p0 = pt(CGPoint(x: o.x, y: o.y + dy * arm))
            let pc = pt(o)
            let p1 = pt(CGPoint(x: o.x + dx * arm, y: o.y))
            let path = CGMutablePath()
            path.move(to: p0)
            path.addArc(tangent1End: pc, tangent2End: p1, radius: radius * k)
            path.addLine(to: p1)
            ctx.addPath(path)
            ctx.strokePath()
        case .polyline(let points):
            let path = CGMutablePath()
            path.addLines(between: points.map(pt))
            ctx.addPath(path)
            ctx.strokePath()
        case .curve(let p):
            var t = CGAffineTransform(scaleX: k, y: k)
            if let scaled = p.copy(using: &t) { ctx.addPath(scaled) }
            ctx.strokePath()
        }
    }
    return ctx.makeImage()!
}

/// The current glyph (AppShell's StatusItemIcon.drawn, 18-pt design), for comparison.
func drawCurrentGlyph(_ ctx: CGContext, size: CGFloat, scale: CGFloat) {
    let k = size * scale / 18
    ctx.saveGState()
    ctx.scaleBy(x: k, y: k)
    let back = CGPath(roundedRect: CGRect(x: 6.25, y: 2.25, width: 10, height: 8), cornerWidth: 2, cornerHeight: 2, transform: nil)
    ctx.setLineWidth(1.5)
    ctx.addPath(back)
    ctx.strokePath()
    let front = CGRect(x: 1.75, y: 6.75, width: 11.5, height: 9)
    ctx.setBlendMode(.clear)
    ctx.addPath(CGPath(roundedRect: front.insetBy(dx: -1.5, dy: -1.5), cornerWidth: 3.2, cornerHeight: 3.2, transform: nil))
    ctx.fillPath()
    ctx.setBlendMode(.normal)
    ctx.setLineWidth(1.6)
    ctx.addPath(CGPath(roundedRect: front, cornerWidth: 2.2, cornerHeight: 2.2, transform: nil))
    ctx.strokePath()
    let tick = CGMutablePath()
    tick.move(to: CGPoint(x: 4.6, y: 12.6))
    tick.addCurve(to: CGPoint(x: 10.4, y: 9.6), control1: CGPoint(x: 6.4, y: 9.4), control2: CGPoint(x: 8.2, y: 12.8))
    ctx.setLineCap(.round)
    ctx.addPath(tick)
    ctx.strokePath()
    ctx.restoreGState()
}

// MARK: - Sheet drawing helpers (sheet canvas is y-down, in points, rendered at 2x)

struct Sheet {
    let ctx: CGContext
    let scale: CGFloat

    init(width: CGFloat, height: CGFloat, scale: CGFloat) {
        self.scale = scale
        ctx = CGContext(data: nil, width: Int(width * scale), height: Int(height * scale), bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: height * scale)
        ctx.scaleBy(x: scale, y: -scale)
        ctx.interpolationQuality = .none
    }

    func fill(_ r: CGRect, _ c: CGColor, radius: CGFloat = 0) {
        ctx.setFillColor(c)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil))
        ctx.fillPath()
    }

    func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor) {
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        (s as NSString).draw(at: p, withAttributes: [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color])
        NSGraphicsContext.restoreGraphicsState()
    }

    /// Draws a white-on-clear mask tinted with `color` in `rect` (y-down).
    func mask(_ image: CGImage, in rect: CGRect, color: CGColor) {
        ctx.saveGState()
        ctx.translateBy(x: rect.minX, y: rect.maxY)
        ctx.scaleBy(x: 1, y: -1)
        let r = CGRect(origin: .zero, size: rect.size)
        ctx.clip(to: r, mask: image)
        ctx.setFillColor(color)
        ctx.fill(r)
        ctx.restoreGState()
    }

    func write(_ url: URL) {
        let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
        rep.size = NSSize(width: CGFloat(rep.pixelsWide) / scale, height: CGFloat(rep.pixelsHigh) / scale)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}

// Generic neighbours drawn here (no real third-party icons).
func neighbourGlyph(_ kind: Int, size: Int, scale: Int) -> CGImage {
    let px = size * scale
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(px)); ctx.scaleBy(x: 1, y: -1)
    let k = CGFloat(px) / 16
    ctx.scaleBy(x: k, y: k)
    ctx.setFillColor(.white); ctx.setStrokeColor(.white); ctx.setLineWidth(1.5); ctx.setLineCap(.round)
    switch kind {
    case 0: // four rounded squares
        for (x, y) in [(2.5, 2.5), (9, 2.5), (2.5, 9), (9, 9)] {
            ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: 4.5, height: 4.5), cornerWidth: 1.2, cornerHeight: 1.2, transform: nil))
        }
        ctx.fillPath()
    case 1: // magnifier
        ctx.strokeEllipse(in: CGRect(x: 2.5, y: 2.5, width: 8, height: 8))
        ctx.move(to: CGPoint(x: 9.6, y: 9.6)); ctx.addLine(to: CGPoint(x: 13.5, y: 13.5)); ctx.strokePath()
    default: // battery
        ctx.setLineWidth(1.1)
        ctx.addPath(CGPath(roundedRect: CGRect(x: 0.8, y: 4.5, width: 12.5, height: 7), cornerWidth: 2, cornerHeight: 2, transform: nil)); ctx.strokePath()
        ctx.fill(CGRect(x: 2.3, y: 6, width: 7.5, height: 4))
        ctx.addPath(CGPath(roundedRect: CGRect(x: 14, y: 6.5, width: 1.4, height: 3), cornerWidth: 0.6, cornerHeight: 0.6, transform: nil)); ctx.fillPath()
    }
    return ctx.makeImage()!
}

// MARK: - Sheets

let recommended: Option = .framedCamera
let candidates: [Option?] = [nil] + Option.allCases.map { $0 }
func label(_ o: Option?) -> String { o.map { $0.rawValue + ($0 == recommended ? "   ★ recommended" : "") } ?? "Current glyph (stacked cards)" }

let lightBar = CGColor(srgbRed: 0.93, green: 0.93, blue: 0.94, alpha: 1)
let darkBar = CGColor(srgbRed: 0.14, green: 0.14, blue: 0.16, alpha: 1)
let lightInk = CGColor(gray: 0, alpha: 0.85)
let darkInk = CGColor(gray: 1, alpha: 0.92)
let amber = CGColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)

/// One mock menu bar (24 pt tall) with the glyph at `size` between neighbours.
func menuBar(_ s: Sheet, origin: CGPoint, width: CGFloat, dark: Bool, glyph: Option?, size: Int, tint: CGColor? = nil) {
    let bg = dark ? darkBar : lightBar, ink = dark ? darkInk : lightInk
    s.fill(CGRect(x: origin.x, y: origin.y, width: width, height: 24), bg, radius: 4)
    var x = origin.x + 14
    func glyphAt(_ img: CGImage, _ pts: CGFloat, _ color: CGColor) {
        s.mask(img, in: CGRect(x: x, y: origin.y + (24 - pts) / 2, width: pts, height: pts), color: color)
        x += pts + 16
    }
    glyphAt(neighbourGlyph(0, size: 16, scale: 2), 16, ink)
    glyphAt(renderGlyph(glyph, size: size, scale: 2), CGFloat(size), tint ?? ink)
    glyphAt(neighbourGlyph(1, size: 16, scale: 2), 16, ink)
    glyphAt(neighbourGlyph(2, size: 16, scale: 2), 16, ink)
    s.text("Thu 14:32", at: CGPoint(x: x, y: origin.y + 4), size: 13, weight: .medium,
           color: NSColor(cgColor: ink) ?? .black)
}

func overviewSheet(to url: URL) {
    let barW: CGFloat = 230, colGap: CGFloat = 16, rowH: CGFloat = 132
    let width = 24 + 3 * (barW + colGap) + barW + 24
    let height = 70 + CGFloat(candidates.count) * rowH + 20
    let s = Sheet(width: width, height: height, scale: 2)
    s.fill(CGRect(x: 0, y: 0, width: width, height: height), CGColor(gray: 1, alpha: 1))
    s.text("ShotZ menu-bar glyph options — actual size (view at 100 % on a Retina display)", at: CGPoint(x: 24, y: 16), size: 15, weight: .semibold, color: .black)
    s.text("Columns: 16 pt · 18 pt · 22 pt · DEV amber (18 pt). Each in a light and a dark menu bar between generic neighbours.",
           at: CGPoint(x: 24, y: 38), size: 11, color: .darkGray)
    for (i, option) in candidates.enumerated() {
        let y = 70 + CGFloat(i) * rowH
        if option == recommended { s.fill(CGRect(x: 12, y: y - 6, width: width - 24, height: rowH - 8), CGColor(srgbRed: 1, green: 0.95, blue: 0.75, alpha: 1), radius: 8) }
        s.text(label(option), at: CGPoint(x: 24, y: y), size: 13, weight: .semibold, color: .black)
        for (c, size) in [16, 18, 22, 18].enumerated() {
            let x = 24 + CGFloat(c) * (barW + colGap)
            let tint: CGColor? = c == 3 ? amber : nil
            menuBar(s, origin: CGPoint(x: x, y: y + 24), width: barW, dark: false, glyph: option, size: size, tint: tint)
            menuBar(s, origin: CGPoint(x: x, y: y + 56), width: barW, dark: true, glyph: option, size: size, tint: tint)
            s.text(c == 3 ? "DEV · 18 pt" : "\(size) pt", at: CGPoint(x: x, y: y + 86), size: 10, color: .gray)
        }
    }
    s.write(url)
}

/// Every glyph at 1x and 2x for each size, enlarged with visible pixels.
func pixelSheet(to url: URL) {
    let cell: CGFloat = 22 * 6 + 16 // largest glyph at 6 sheet-points per 1x pixel
    let cols = 6 // (16, 18, 22) × (1x, 2x)
    let width = 220 + CGFloat(cols) * cell
    let rowH = cell + 26
    let height = 60 + CGFloat(candidates.count) * rowH
    let s = Sheet(width: width, height: height, scale: 1)
    s.fill(CGRect(x: 0, y: 0, width: width, height: height), CGColor(gray: 1, alpha: 1))
    s.text("Pixel view: each glyph rendered at 1x and 2x, enlarged (same physical size per point size)", at: CGPoint(x: 16, y: 14), size: 15, weight: .semibold, color: .black)
    var col = 0
    for size in [16, 18, 22] {
        for scale in [1, 2] {
            s.text("\(size) pt @\(scale)x · \(strokePixels(size: size, scale: scale)) px", at: CGPoint(x: 220 + CGFloat(col) * cell, y: 38), size: 11, color: .darkGray)
            col += 1
        }
    }
    for (i, option) in candidates.enumerated() {
        let y = 60 + CGFloat(i) * rowH
        s.text(label(option), at: CGPoint(x: 16, y: y + cell / 2 - 8), size: 12, weight: .semibold, color: .black)
        var c = 0
        for size in [16, 18, 22] {
            for scale in [1, 2] {
                let side = CGFloat(size) * 6
                let r = CGRect(x: 220 + CGFloat(c) * cell, y: y, width: side, height: side)
                s.fill(r, CGColor(gray: 0.95, alpha: 1))
                s.mask(renderGlyph(option, size: size, scale: scale), in: r, color: CGColor(gray: 0.1, alpha: 1))
                // Pixel grid.
                let step = 6 / CGFloat(scale)
                s.ctx.setStrokeColor(CGColor(gray: 0.5, alpha: 0.18)); s.ctx.setLineWidth(0.5)
                var g: CGFloat = 0
                while g <= side + 0.01 {
                    s.ctx.move(to: CGPoint(x: r.minX + g, y: r.minY)); s.ctx.addLine(to: CGPoint(x: r.minX + g, y: r.maxY))
                    s.ctx.move(to: CGPoint(x: r.minX, y: r.minY + g)); s.ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY + g))
                    g += step
                }
                s.ctx.strokePath()
                c += 1
            }
        }
    }
    s.write(url)
}

// MARK: - Main

let args = CommandLine.arguments
guard args.count > 1 else {
    print("usage: swift scripts/menubar-glyph-options.swift <output-dir>")
    exit(1)
}
let out = URL(fileURLWithPath: args[1], isDirectory: true)
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
overviewSheet(to: out.appendingPathComponent("menubar-options@2x.png"))
pixelSheet(to: out.appendingPathComponent("menubar-pixels.png"))
print("Wrote \(out.path)/menubar-options@2x.png and menubar-pixels.png (recommended: \(recommended.rawValue))")
