import CoreGraphics
import CoreText
import Foundation
import ImageIO
@testable import AnnotationKit

/// Deterministic synthetic base images for renderer tests (no real screen content).
enum TestImages {
    static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Soft gradient, a light grid, a dark band and a few lines of sample text.
    static func base(width: Int, height: Int, text: Bool = true) -> CGImage {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let w = CGFloat(width), h = CGFloat(height)
        let g = CGGradient(colorsSpace: sRGB, colors: [
            CGColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
            CGColor(srgbRed: 0.74, green: 0.81, blue: 0.90, alpha: 1),
        ] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(g, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
        ctx.setStrokeColor(CGColor(gray: 0.3, alpha: 0.12))
        ctx.setLineWidth(1)
        let step = max(w, h) / 32
        var x: CGFloat = 0
        while x < w { ctx.move(to: CGPoint(x: x, y: 0)); ctx.addLine(to: CGPoint(x: x, y: h)); x += step }
        var y: CGFloat = 0
        while y < h { ctx.move(to: CGPoint(x: 0, y: y)); ctx.addLine(to: CGPoint(x: w, y: y)); y += step }
        ctx.strokePath()
        ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.18, blue: 0.24, alpha: 1))
        ctx.fill(CGRect(x: 0, y: h * 0.28, width: w, height: h * 0.1)) // rows 62–72 % from the top
        if text {
            let size = max(h / 30, 8)
            let font = CTFontCreateWithName("Helvetica" as CFString, size, nil)
            let lines = ["Account 4417 1234 5678 9010", "password: correct-horse-battery", "The quick brown fox jumps over"]
            for (i, s) in lines.enumerated() {
                let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0.1, alpha: 1)]
                let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
                // Baselines at 82 %, 86.5 %, 91 % from the top (CG is y-up).
                ctx.textPosition = CGPoint(x: w * 0.03, y: h * (1 - 0.82) - CGFloat(i) * h * 0.045)
                CTLineDraw(line, ctx)
            }
        }
        return ctx.makeImage()!
    }

    static func writePNG(_ image: CGImage, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    static var packageRoot: URL {
        URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }
}
