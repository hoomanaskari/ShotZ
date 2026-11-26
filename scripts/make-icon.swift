// Draws Shotz's original placeholder app icon and writes Resources/AppIcon.icns.
// Usage: swift scripts/make-icon.swift   (from any directory)
import AppKit
import Foundation

let scriptDir = URL(filePath: CommandLine.arguments[0]).deletingLastPathComponent()
let root = scriptDir.deletingLastPathComponent()
let iconset = FileManager.default.temporaryDirectory.appending(path: "Shotz-\(UUID().uuidString).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Squircle-ish tile with margin, per macOS icon grid proportions.
    let inset = s * 0.1
    let tile = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)
    let path = CGPath(roundedRect: tile, cornerWidth: tile.width * 0.225, cornerHeight: tile.width * 0.225, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.03, color: CGColor(gray: 0, alpha: 0.35))
    ctx.addPath(path)
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [
        CGColor(srgbRed: 0.98, green: 0.42, blue: 0.29, alpha: 1),
        CGColor(srgbRed: 0.86, green: 0.18, blue: 0.47, alpha: 1),
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])
    ctx.restoreGState()

    // Four viewfinder corner brackets.
    let frame = tile.insetBy(dx: tile.width * 0.2, dy: tile.width * 0.2)
    let arm = frame.width * 0.28
    ctx.setStrokeColor(CGColor(gray: 1, alpha: 1))
    ctx.setLineWidth(tile.width * 0.055)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    for (cx, cy, dx, dy) in [(frame.minX, frame.minY, 1.0, 1.0), (frame.maxX, frame.minY, -1.0, 1.0),
                             (frame.minX, frame.maxY, 1.0, -1.0), (frame.maxX, frame.maxY, -1.0, -1.0)] {
        ctx.move(to: CGPoint(x: cx, y: cy + dy * arm))
        ctx.addLine(to: CGPoint(x: cx, y: cy))
        ctx.addLine(to: CGPoint(x: cx + dx * arm, y: cy))
    }
    ctx.strokePath()

    // A bold "z" stroke in the centre.
    let z = frame.insetBy(dx: frame.width * 0.3, dy: frame.width * 0.3)
    ctx.setLineWidth(tile.width * 0.06)
    ctx.move(to: CGPoint(x: z.minX, y: z.maxY))
    ctx.addLine(to: CGPoint(x: z.maxX, y: z.maxY))
    ctx.addLine(to: CGPoint(x: z.minX, y: z.minY))
    ctx.addLine(to: CGPoint(x: z.maxX, y: z.minY))
    ctx.strokePath()

    let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try render(base).write(to: iconset.appending(path: "icon_\(base)x\(base).png"))
    try render(base * 2).write(to: iconset.appending(path: "icon_\(base)x\(base)@2x.png"))
}
let output = root.appending(path: "Resources/AppIcon.icns")
let p = Process()
p.executableURL = URL(filePath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try p.run()
p.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
guard p.terminationStatus == 0 else { fatalError("iconutil failed") }
print("Wrote \(output.path)")
