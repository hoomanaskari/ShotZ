// Synthetic sample captures for the README screenshots (no real screen content).
// Usage: swift scripts/screenshots/samples.swift <output-folder>
// Writes "Sign-ups report.png" (the editor sample), notes.png, photo.png and banner.png,
// tagged 144 dpi like Retina captures.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 2 else {
    FileHandle.standardError.write(Data("usage: swift scripts/screenshots/samples.swift <output-folder>\n".utf8))
    exit(64)
}
let folder = URL(filePath: args[1], directoryHint: .isDirectory)
try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((hex >> 16) & 0xff) / 255, green: CGFloat((hex >> 8) & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}

/// Draws into a top-left-origin context of `size` points at 2×, writes a 144-dpi PNG.
func render(_ name: String, _ size: CGSize, _ draw: (CGRect) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = size
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = ctx
    ctx.cgContext.translateBy(x: 0, y: size.height)
    ctx.cgContext.scaleBy(x: 1, y: -1)
    NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx.cgContext, flipped: true)
    draw(CGRect(origin: .zero, size: size))
    NSGraphicsContext.restoreGraphicsState()
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: folder.appending(path: name))
}

func text(_ s: String, at p: CGPoint, size: CGFloat, weight: NSFont.Weight = .regular, color: NSColor = rgb(0x1d2330), mono: Bool = false) {
    let font = mono ? NSFont.monospacedSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
    (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
}

func rounded(_ r: CGRect, _ radius: CGFloat, fill: NSColor, stroke: NSColor? = nil) {
    let p = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    fill.setFill()
    p.fill()
    if let stroke { stroke.setStroke(); p.lineWidth = 1; p.stroke() }
}

// 1. The editor sample: a plain report card with a bar chart and a settings snippet.
render("Sign-ups report.png", CGSize(width: 800, height: 500)) { b in
    rgb(0xeef1f6).setFill(); b.fill()
    let card = CGRect(x: 40, y: 36, width: 720, height: 428)
    rounded(card, 14, fill: .white, stroke: rgb(0xdde2ea))
    text("Weekly sign-ups", at: CGPoint(x: 72, y: 62), size: 26, weight: .semibold)
    text("Last 8 weeks · all regions", at: CGPoint(x: 72, y: 98), size: 14, color: rgb(0x6b7280))
    let values: [CGFloat] = [0.42, 0.55, 0.48, 0.63, 0.58, 0.71, 0.66, 0.92]
    let base = CGPoint(x: 80, y: 330)
    for i in 0...4 {
        let y = base.y - CGFloat(i) * 46
        rgb(0xe5e7eb).setFill(); CGRect(x: base.x, y: y, width: 400, height: 1).fill()
    }
    for (i, v) in values.enumerated() {
        let h = v * 190, x = base.x + 12 + CGFloat(i) * 49
        rounded(CGRect(x: x, y: base.y - h, width: 30, height: h), 5, fill: i == 7 ? rgb(0x3b82f6) : rgb(0xbfd3f5))
        text("W\(i + 1)", at: CGPoint(x: x + 4, y: base.y + 8), size: 12, color: rgb(0x6b7280))
    }
    let side = CGRect(x: 520, y: 140, width: 210, height: 200)
    rounded(side, 10, fill: rgb(0xf7f8fb), stroke: rgb(0xe5e7eb))
    text("Total", at: CGPoint(x: 540, y: 156), size: 13, color: rgb(0x6b7280))
    text("12,480", at: CGPoint(x: 540, y: 176), size: 30, weight: .bold)
    text("+18% vs last period", at: CGPoint(x: 540, y: 218), size: 13, weight: .medium, color: rgb(0x16a34a))
    text("Top source", at: CGPoint(x: 540, y: 256), size: 13, color: rgb(0x6b7280))
    text("Newsletter", at: CGPoint(x: 540, y: 276), size: 17, weight: .semibold)
    rounded(CGRect(x: 72, y: 382, width: 656, height: 54), 8, fill: rgb(0x111827))
    text("API_TOKEN = \"demo-7f3a-91c2-0b6e-55d1\"", at: CGPoint(x: 92, y: 399), size: 15, color: rgb(0xe5e7eb), mono: true)
}

// 2–4. Varied captures for the quick-access stack.
render("notes.png", CGSize(width: 420, height: 560)) { b in
    rgb(0xfffdf5).setFill(); b.fill()
    text("Release checklist", at: CGPoint(x: 32, y: 32), size: 24, weight: .semibold)
    for (i, item) in ["Write the notes", "Check the build", "Update screenshots", "Tag the release", "Tell the team"].enumerated() {
        let y = 92 + CGFloat(i) * 52
        rounded(CGRect(x: 32, y: y, width: 22, height: 22), 6, fill: i < 3 ? rgb(0x3b82f6) : .white, stroke: rgb(0xcbd5e1))
        text(item, at: CGPoint(x: 68, y: y), size: 18, color: i < 3 ? rgb(0x9ca3af) : rgb(0x1f2937))
    }
}

render("photo.png", CGSize(width: 640, height: 400)) { b in
    let sky = NSGradient(colors: [rgb(0xfcd7a8), rgb(0xf59e8b), rgb(0x7c6fd8)])!
    sky.draw(in: b, angle: -90)
    rgb(0xfff2c8, 0.95).setFill()
    NSBezierPath(ovalIn: CGRect(x: 380, y: 120, width: 110, height: 110)).fill()
    for (i, c) in [rgb(0x4c3f91), rgb(0x2f2a66), rgb(0x1c1940)].enumerated() {
        let p = NSBezierPath()
        let top = 250 + CGFloat(i) * 40
        p.move(to: CGPoint(x: 0, y: b.maxY))
        p.line(to: CGPoint(x: 0, y: top))
        for x in stride(from: 0, through: 640, by: 80) {
            p.line(to: CGPoint(x: CGFloat(x) + 40, y: top - CGFloat((x / 80 + i) % 3) * 28 - 10))
            p.line(to: CGPoint(x: CGFloat(x) + 80, y: top))
        }
        p.line(to: CGPoint(x: 640, y: b.maxY))
        c.setFill(); p.fill()
    }
}

render("banner.png", CGSize(width: 900, height: 220)) { b in
    let g = NSGradient(colors: [rgb(0x0ea5e9), rgb(0x6366f1)])!
    g.draw(in: b, angle: 0)
    text("Ship day", at: CGPoint(x: 48, y: 60), size: 52, weight: .heavy, color: .white)
    text("Everything you need, in one place.", at: CGPoint(x: 52, y: 132), size: 22, color: rgb(0xffffff, 0.85))
}
print("samples written to \(folder.path)")
