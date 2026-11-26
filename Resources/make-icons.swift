// Builds ShotZ's app icons (and, optionally, the menu-bar glyph) from the owner's artwork.
// Run it through scripts/make-icons.sh, which picks the inputs and output paths; see docs/ICON.md.
//
//   swift Resources/make-icons.swift [--master <file>] [--glyph <file>] --out <dir> [--glyph-swift <file>]
//
// --master  a square app icon master: PNG (at least 1024×1024), SVG or PDF (first page).
//           Writes <out>/AppIcon.icns (every size, 16 to 1024 including @2x) and
//           <out>/AppIcon-Dev.icns (the same art with an amber DEV band clipped to its shape).
//           Vector masters are drawn at each size; PNG masters are downsampled by repeated
//           halving with high-quality interpolation (no edge halo).
//           The artwork is never reshaped: a master that is not a macOS-style rounded tile is
//           used as it is, with a note.
// --glyph   a menu-bar glyph master: PNG, SVG or PDF, one colour on a transparent background.
//           Writes <glyph-swift> with the glyph as an 18 pt template image (1x and 2x PNG), which
//           StatusItemIcon loads instead of its drawn glyph. The amber dev tint stays in code.
// Uses only system frameworks (AppKit, CoreGraphics, CoreText, ImageIO) and /usr/bin/iconutil.
import AppKit
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icons: \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) { print("make-icons: \(message)") }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: Arguments

var masterPath: String?
var glyphPath: String?
var outPath: String?
var glyphSwiftPath: String?
var args = Array(CommandLine.arguments.dropFirst())
while !args.isEmpty {
    let flag = args.removeFirst()
    guard let value = args.first, !value.hasPrefix("--") else { fail("\(flag) needs a value") }
    args.removeFirst()
    switch flag {
    case "--master": masterPath = value
    case "--glyph": glyphPath = value
    case "--out": outPath = value
    case "--glyph-swift": glyphSwiftPath = value
    default: fail("unknown option \(flag)")
    }
}
guard let outPath else { fail("--out <dir> is required") }
guard masterPath != nil || glyphPath != nil else { fail("nothing to do: give --master and/or --glyph") }
let outDir = URL(filePath: outPath, directoryHint: .isDirectory)

// MARK: Loading artwork

/// Artwork that can be drawn into a bitmap at any pixel size.
enum Artwork {
    case raster(CGImage)
    case vector(NSImage)

    /// Loads and checks a master: known format by content, square, and (for PNG) big enough.
    static func load(_ path: String, role: String, minimumPixels: Int) -> Artwork {
        let url = URL(filePath: path)
        guard let data = try? Data(contentsOf: url) else { fail("\(role): can't read \(path)") }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png":
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String?, type == UTType.png.identifier,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { fail("\(role): \(path) has a .png name but is not a PNG file") }
            guard image.width == image.height else {
                fail("\(role): \(path) is \(image.width)×\(image.height); it must be square")
            }
            guard image.width >= minimumPixels else {
                fail("\(role): \(path) is \(image.width)×\(image.height); it must be at least \(minimumPixels)×\(minimumPixels)")
            }
            return .raster(image)
        case "svg", "pdf":
            let looksRight = ext == "pdf"
                ? data.starts(with: Data("%PDF".utf8))
                : (String(data: data.prefix(4096), encoding: .utf8) ?? "").contains("<svg")
            guard looksRight else { fail("\(role): \(path) has a .\(ext) name but is not an \(ext.uppercased()) file") }
            guard let image = NSImage(data: data), image.size.width > 0, image.size.height > 0 else {
                fail("\(role): macOS can't draw \(path)")
            }
            let ratio = image.size.width / image.size.height
            guard abs(ratio - 1) < 0.005 else {
                fail("\(role): \(path) is \(Int(image.size.width))×\(Int(image.size.height)) pt; it must be square")
            }
            return .vector(image)
        default:
            fail("\(role): \(path): use a PNG, SVG or PDF file (got .\(ext.isEmpty ? "no extension" : ext))")
        }
    }

    /// The artwork filling a px×px transparent sRGB bitmap.
    func bitmap(_ px: Int) -> CGContext {
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let rect = CGRect(x: 0, y: 0, width: px, height: px)
        switch self {
        case .raster(let image):
            ctx.interpolationQuality = .high
            ctx.draw(Self.resample(image, to: px), in: rect)
        case .vector(let image):
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
            image.draw(in: rect, from: .zero, operation: .copy, fraction: 1)
            NSGraphicsContext.restoreGraphicsState()
        }
        return ctx
    }

    /// High-quality downsampling to exactly px×px: halve with Core Graphics' high-quality
    /// interpolation until within 2× of the target, then one last step. Each step averages
    /// cleanly, so edges keep no halo (a single Lanczos pass rings at large reductions).
    private static func resample(_ image: CGImage, to px: Int) -> CGImage {
        var current = image
        while current.width != px {
            let next = max(px, current.width / 2)
            let ctx = CGContext(data: nil, width: next, height: next, bitsPerComponent: 8, bytesPerRow: 0,
                                space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.interpolationQuality = .high
            ctx.draw(current, in: CGRect(x: 0, y: 0, width: next, height: next))
            current = ctx.makeImage()!
        }
        return current
    }
}

/// Alpha of each pixel (row 0 at the top), for shape checks.
func alphaPlane(_ ctx: CGContext) -> (values: [UInt8], width: Int, height: Int) {
    let image = ctx.makeImage()!
    let w = image.width, h = image.height
    var alpha = [UInt8](repeating: 0, count: w * h)
    let mask = CGContext(data: &alpha, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    mask.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
    return (alpha, w, h)
}

/// Bounding box of pixels with alpha > threshold, in CoreGraphics coordinates (origin bottom left).
func alphaBounds(_ ctx: CGContext, threshold: UInt8 = 8) -> CGRect? {
    let (a, w, h) = alphaPlane(ctx)
    var minX = w, minY = h, maxX = -1, maxY = -1
    for y in 0..<h {
        for x in 0..<w where a[y * w + x] > threshold {
            minX = min(minX, x); maxX = max(maxX, x)
            minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    guard maxX >= 0 else { return nil }
    // Rows above are top-down; flip to CoreGraphics' bottom-up space.
    return CGRect(x: minX, y: h - 1 - maxY, width: maxX - minX + 1, height: maxY - minY + 1)
}

func png(_ ctx: CGContext) -> Data {
    let data = NSMutableData()
    let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    CGImageDestinationFinalize(dest)
    return data as Data
}

// MARK: App icons

/// The amber band with "DEV" (text from 64 px up), clipped to the artwork's own alpha.
func addDevBand(_ ctx: CGContext, px: Int, art: CGRect) {
    let amber = CGColor(srgbRed: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
    let band = CGRect(x: art.minX, y: art.minY + art.height * 0.07, width: art.width,
                      height: art.height * (px <= 32 ? 0.22 : 0.19))
    ctx.saveGState()
    ctx.setBlendMode(.sourceAtop)   // paints only where the artwork already is
    ctx.setFillColor(amber)
    ctx.fill(band)
    if px >= 64 {
        let font = CTFontCreateUIFontForLanguage(.emphasizedSystem, art.height * 0.13, nil)!
        let text = NSAttributedString(string: "DEV", attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1F / 255, alpha: 1),
            NSAttributedString.Key(kCTKernAttributeName as String): art.height * 0.025,
        ])
        let line = CTLineCreateWithAttributedString(text)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        ctx.textPosition = CGPoint(x: band.midX - glyphs.width / 2 - glyphs.minX, y: band.midY - glyphs.height / 2 - glyphs.minY)
        CTLineDraw(line, ctx)
    }
    ctx.restoreGState()
}

/// Notes (never errors) on how the master compares with a macOS icon tile.
func describeShape(_ art: Artwork) {
    let ctx = art.bitmap(1024)
    let (a, w, h) = alphaPlane(ctx)
    func alpha(_ fx: Double, _ fy: Double) -> UInt8 { a[Int(fy * Double(h - 1)) * w + Int(fx * Double(w - 1))] }
    guard let bounds = alphaBounds(ctx) else { fail("master: the artwork is fully transparent") }
    let opaqueCorners = [alpha(0.02, 0.02), alpha(0.98, 0.02), alpha(0.02, 0.98), alpha(0.98, 0.98)].filter { $0 > 128 }.count
    if a.allSatisfy({ $0 == 255 }) {
        note("master is fully opaque (no transparency): it is not a macOS-style rounded tile. Used as is, not reshaped.")
    } else if opaqueCorners > 0 {
        note("master has opaque corners: it is not a macOS-style rounded tile. Used as is, not reshaped.")
    } else if bounds.minX < 40 || bounds.minY < 40 {
        note("master artwork reaches the canvas edge; macOS tiles leave about 100 px of 1024 around the tile. Used as is.")
    } else {
        note("master looks like a macOS-style tile (artwork \(Int(bounds.width))×\(Int(bounds.height)) px of 1024).")
    }
}

func writeIcns(_ art: Artwork, dev: Bool, to output: URL) {
    let fm = FileManager.default
    let iconset = fm.temporaryDirectory.appending(path: "ShotZ-\(UUID().uuidString).iconset")
    do {
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        for base in [16, 32, 128, 256, 512] {
            for (scale, suffix) in [(1, ""), (2, "@2x")] {
                let px = base * scale
                let ctx = art.bitmap(px)
                if dev, let bounds = alphaBounds(ctx) { addDevBand(ctx, px: px, art: bounds) }
                try png(ctx).write(to: iconset.appending(path: "icon_\(base)x\(base)\(suffix).png"))
            }
        }
        let p = Process()
        p.executableURL = URL(filePath: "/usr/bin/iconutil")
        p.arguments = ["-c", "icns", iconset.path, "-o", output.path]
        try p.run()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else { fail("iconutil failed for \(output.path)") }
    } catch {
        fail("writing \(output.path): \(error.localizedDescription)")
    }
    note("wrote \(output.path)")
}

// MARK: Menu-bar glyph

/// The glyph as a template mask: black with the master's alpha, trimmed and fitted into a
/// 16 pt square centred on the 18 pt canvas the menu bar uses.
func glyphPNG(_ art: Artwork, scale: Int) -> Data {
    let master = art.bitmap(1024)
    guard let bounds = alphaBounds(master) else { fail("glyph: the artwork is fully transparent") }
    let (a, _, _) = alphaPlane(master)
    if a.allSatisfy({ $0 == 255 }) {
        fail("glyph: the master has no transparency; it must be one colour on a transparent background")
    }
    let canvas = 18 * scale
    let box = CGFloat(16 * scale)
    let fit = box / max(bounds.width, bounds.height)
    let size = CGSize(width: bounds.width * fit, height: bounds.height * fit)
    let origin = CGPoint(x: (CGFloat(canvas) - size.width) / 2, y: (CGFloat(canvas) - size.height) / 2)

    let ctx = CGContext(data: nil, width: canvas, height: canvas, bitsPerComponent: 8, bytesPerRow: 0,
                        space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    let trimmed = master.makeImage()!.cropping(to: CGRect(x: bounds.minX, y: 1024 - bounds.maxY, width: bounds.width, height: bounds.height))!
    ctx.clip(to: CGRect(origin: origin, size: size), mask: maskImage(trimmed))
    ctx.setFillColor(CGColor(gray: 0, alpha: 1))
    ctx.fill(CGRect(x: 0, y: 0, width: canvas, height: canvas))
    return png(ctx)
}

/// An image whose alpha becomes a clipping mask (only the shape counts, not its colours).
func maskImage(_ image: CGImage) -> CGImage {
    var alpha = [UInt8](repeating: 0, count: image.width * image.height)
    let ctx = CGContext(data: &alpha, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                        space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)!
    ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
    let gray = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width,
                         space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
    let data = gray.data!.bindMemory(to: UInt8.self, capacity: alpha.count)
    for i in alpha.indices { data[i] = alpha[i] }
    return gray.makeImage()!
}

func writeGlyphSwift(_ art: Artwork, to output: URL) {
    let one = glyphPNG(art, scale: 1).base64EncodedString()
    let two = glyphPNG(art, scale: 2).base64EncodedString()
    let source = """
    // Generated by scripts/make-icons.sh --glyph from Resources/icon-master/. Do not edit.
    // The menu-bar glyph as an 18 pt template image (1x and 2x PNG, black on transparent).
    import Foundation

    enum MenuBarGlyphArt {
        static let png1x: String? = "\(one)"
        static let png2x: String? = "\(two)"
    }

    """
    do { try source.write(to: output, atomically: true, encoding: .utf8) } catch {
        fail("writing \(output.path): \(error.localizedDescription)")
    }
    note("wrote \(output.path)")
}

// MARK: Run

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
if let masterPath {
    let art = Artwork.load(masterPath, role: "master", minimumPixels: 1024)
    describeShape(art)
    writeIcns(art, dev: false, to: outDir.appending(path: "AppIcon.icns"))
    writeIcns(art, dev: true, to: outDir.appending(path: "AppIcon-Dev.icns"))
}
if let glyphPath {
    guard let glyphSwiftPath else { fail("--glyph needs --glyph-swift <file>") }
    let art = Artwork.load(glyphPath, role: "glyph", minimumPixels: 36)
    writeGlyphSwift(art, to: URL(filePath: glyphSwiftPath))
}
