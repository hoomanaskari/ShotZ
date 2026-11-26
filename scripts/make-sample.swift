// Writes a neutral synthetic test PNG (gradient, shapes, text) at a given pixel size.
// Usage: swift scripts/make-sample.swift <width> <height> <output.png>
//   e.g. swift scripts/make-sample.swift 5120 2880 build/sample-5k.png
// The PNG is tagged 144 dpi (scale 2), like a Retina capture.
import AppKit
import Foundation

let args = CommandLine.arguments
guard args.count == 4, let width = Int(args[1]), let height = Int(args[2]), width > 0, height > 0 else {
    FileHandle.standardError.write(Data("usage: swift scripts/make-sample.swift <width> <height> <output.png>\n".utf8))
    exit(64)
}
let output = URL(filePath: args[3], relativeTo: URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory))

guard let space = CGColorSpace(name: CGColorSpace.sRGB),
      let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                          space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
else { fatalError("cannot create context") }

let w = CGFloat(width), h = CGFloat(height), unit = min(w, h) / 100

// Background: soft diagonal gradient.
let gradient = CGGradient(colorsSpace: space, colors: [
    CGColor(srgbRed: 0.90, green: 0.93, blue: 0.97, alpha: 1),
    CGColor(srgbRed: 0.72, green: 0.80, blue: 0.90, alpha: 1),
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])

// A grid of thin lines every 10 units, so scaling and cropping are easy to judge.
ctx.setStrokeColor(CGColor(gray: 0.3, alpha: 0.15))
ctx.setLineWidth(max(1, unit * 0.1))
var x: CGFloat = 0
while x <= w { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)); x += unit * 10 }
var y: CGFloat = 0
while y <= h { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)); y += unit * 10 }
ctx.strokePath()

// A fake "window" card with title bar and content rows.
let card = CGRect(x: w * 0.08, y: h * 0.12, width: w * 0.5, height: h * 0.7)
ctx.setShadow(offset: CGSize(width: 0, height: -unit), blur: unit * 3, color: CGColor(gray: 0, alpha: 0.25))
ctx.setFillColor(CGColor(gray: 1, alpha: 1))
ctx.addPath(CGPath(roundedRect: card, cornerWidth: unit * 2, cornerHeight: unit * 2, transform: nil))
ctx.fillPath()
ctx.setShadow(offset: .zero, blur: 0, color: nil)
ctx.setFillColor(CGColor(gray: 0.94, alpha: 1))
ctx.fill(CGRect(x: card.minX, y: card.maxY - unit * 6, width: card.width, height: unit * 4))
for (i, gray) in [0.75, 0.82, 0.88].enumerated() {
    ctx.setFillColor(CGColor(gray: gray, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: card.minX + unit * (2 + CGFloat(i) * 3), y: card.maxY - unit * 4.8, width: unit * 1.8, height: unit * 1.8))
}
for row in 0..<8 {
    let rowWidth = card.width * (0.55 + 0.35 * CGFloat((row * 37) % 10) / 10)
    ctx.setFillColor(CGColor(gray: 0.85, alpha: 1))
    ctx.fill(CGRect(x: card.minX + unit * 3, y: card.maxY - unit * (16 + CGFloat(row) * 5.5), width: rowWidth - unit * 6, height: unit * 2))
}

// Coloured shapes on the right.
ctx.setFillColor(CGColor(srgbRed: 0.20, green: 0.55, blue: 0.85, alpha: 1))
ctx.fillEllipse(in: CGRect(x: w * 0.66, y: h * 0.55, width: unit * 20, height: unit * 20))
ctx.setFillColor(CGColor(srgbRed: 0.95, green: 0.65, blue: 0.20, alpha: 1))
ctx.fill(CGRect(x: w * 0.72, y: h * 0.18, width: unit * 22, height: unit * 14))
ctx.setStrokeColor(CGColor(srgbRed: 0.30, green: 0.65, blue: 0.40, alpha: 1))
ctx.setLineWidth(unit * 1.2)
ctx.move(to: CGPoint(x: w * 0.64, y: h * 0.45))
ctx.addLine(to: CGPoint(x: w * 0.92, y: h * 0.50))
ctx.strokePath()

// Text: title in the card plus a size label in the corner.
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
func draw(_ string: String, at point: CGPoint, size: CGFloat, weight: NSFont.Weight, color: NSColor) {
    NSAttributedString(string: string, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color,
    ]).draw(at: point)
}
draw("Shotz sample image", at: CGPoint(x: card.minX + unit * 3, y: card.maxY - unit * 10.5), size: unit * 3, weight: .semibold, color: .black)
draw("The quick brown fox jumps over the lazy dog. 0123456789",
     at: CGPoint(x: card.minX + unit * 3, y: card.minY + unit * 4), size: unit * 1.6, weight: .regular, color: .darkGray)
draw("\(width) × \(height) px", at: CGPoint(x: w - unit * 28, y: unit * 3), size: unit * 2.4, weight: .medium, color: NSColor(white: 0.2, alpha: 1))
NSGraphicsContext.current = nil

guard let image = ctx.makeImage(),
      let dest = CGImageDestinationCreateWithURL(output as CFURL, "public.png" as CFString, 1, nil)
else { fatalError("cannot create image destination at \(output.path)") }
try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
guard CGImageDestinationFinalize(dest) else { fatalError("cannot write \(output.path)") }
print("Wrote \(output.path) (\(width)×\(height))")
