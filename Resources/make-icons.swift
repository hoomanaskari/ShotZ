// Builds ShotZ's app icons (and, optionally, the menu-bar glyph) from the owner's artwork.
// Run it through scripts/make-icons.sh, which picks the inputs and output paths; see docs/ICON.md.
//
//   swift Resources/make-icons.swift [--tile-config <json> | --master <file>] [--glyph <file>] --out <dir>
//                                    [--glyph-swift <file>] [--preview <dir>]
//
// --tile-config  the default: a cut-out artwork placed on a generated macOS tile. The JSON names the
//           artwork (a transparent PNG next to it) and its scale, offset, gradient strength and
//           contact shadow; see docs/ICON.md. The tile is the standard 824/1024 continuous-corner
//           shape with the usual drop shadow, a white → light-grey gradient (top left to bottom
//           right) and a hairline inner edge. The artwork is centred on its visual weight.
// --master  alternative: a finished square app icon master: PNG (at least 1024×1024), SVG or PDF (first page).
//           Writes <out>/AppIcon.icns (every size, 16 to 1024 including @2x) and
//           <out>/AppIcon-Dev.icns (the same art with an amber DEV band clipped to its shape).
//           Vector masters are drawn at each size; PNG masters are downsampled by repeated
//           halving with high-quality interpolation (no edge halo).
//           The artwork is never reshaped: a master that is not a macOS-style rounded tile is
//           used as it is, with a note.
// --glyph   a menu-bar glyph master: PNG, SVG or PDF, one colour on a transparent background.
//           Writes <glyph-swift> with the glyph as an 18 pt template image (1x and 2x PNG), which
//           StatusItemIcon loads instead of its drawn glyph. The amber dev tint stays in code.
// --preview writes AppIcon[-Dev]-<px>.png at 1024, 128, 64, 32 and 16 px for review.
// Uses only system frameworks (AppKit, SwiftUI's shape geometry, CoreGraphics, CoreText, ImageIO)
// and /usr/bin/iconutil.
import AppKit
import CoreText
import Foundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("make-icons: \(message)\n".utf8))
    exit(1)
}

func note(_ message: String) { print("make-icons: \(message)") }

let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: Arguments

var masterPath: String?
var tileConfigPath: String?
var previewPath: String?
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
    case "--tile-config": tileConfigPath = value
    case "--preview": previewPath = value
    case "--glyph": glyphPath = value
    case "--out": outPath = value
    case "--glyph-swift": glyphSwiftPath = value
    default: fail("unknown option \(flag)")
    }
}
guard let outPath else { fail("--out <dir> is required") }
guard masterPath != nil || tileConfigPath != nil || glyphPath != nil else { fail("nothing to do: give --tile-config, --master and/or --glyph") }
guard masterPath == nil || tileConfigPath == nil else { fail("give either --tile-config or --master, not both") }
let outDir = URL(filePath: outPath, directoryHint: .isDirectory)

// MARK: Loading artwork

/// Artwork that can be drawn into a bitmap at any pixel size.
enum Artwork {
    case raster(CGImage)
    case vector(NSImage)

    /// Loads and checks a master: known format by content, square, and (for PNG) big enough.
    static func load(_ path: String, role: String, minimumPixels: Int, requireSquare: Bool = true) -> Artwork {
        let url = URL(filePath: path)
        guard let data = try? Data(contentsOf: url) else { fail("\(role): can't read \(path)") }
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "png":
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source) as String?, type == UTType.png.identifier,
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
            else { fail("\(role): \(path) has a .png name but is not a PNG file") }
            guard !requireSquare || image.width == image.height else {
                fail("\(role): \(path) is \(image.width)×\(image.height); it must be square")
            }
            guard min(image.width, image.height) >= minimumPixels else {
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
            guard !requireSquare || abs(ratio - 1) < 0.005 else {
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
    private static func resample(_ image: CGImage, to px: Int) -> CGImage { downsample(image, width: px, height: px) }
}

/// High-quality downsampling to exactly width×height: halve with Core Graphics' high-quality
/// interpolation until within 2× of the target, then one last step (no edge halo).
func downsample(_ image: CGImage, width: Int, height: Int) -> CGImage {
    var current = image
    while current.width != width || current.height != height {
        let nw = max(width, current.width / 2), nh = max(height, current.height / 2)
        let ctx = CGContext(data: nil, width: nw, height: nh, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.interpolationQuality = .high
        ctx.draw(current, in: CGRect(x: 0, y: 0, width: nw, height: nh))
        current = ctx.makeImage()!
    }
    return current
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
func addDevBand(_ ctx: CGContext, px: Int, art: CGRect, clip: CGPath? = nil) {
    let amber = CGColor(srgbRed: 1, green: 0x9F / 255, blue: 0x0A / 255, alpha: 1)
    let band = CGRect(x: art.minX, y: art.minY + art.height * 0.07, width: art.width,
                      height: art.height * (px <= 32 ? 0.22 : 0.19))
    ctx.saveGState()
    if let clip { ctx.addPath(clip); ctx.clip() }
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
    writeIcns(to: output) { px in
        let ctx = art.bitmap(px)
        if dev, let bounds = alphaBounds(ctx) { addDevBand(ctx, px: px, art: bounds) }
        return ctx
    }
}

/// Writes an .icns with every size macOS uses, each rendered by `render(px)`.
func writeIcns(to output: URL, render: (Int) -> CGContext) {
    let fm = FileManager.default
    let iconset = fm.temporaryDirectory.appending(path: "ShotZ-\(UUID().uuidString).iconset")
    do {
        try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: iconset) }
        for base in [16, 32, 128, 256, 512] {
            for (scale, suffix) in [(1, ""), (2, "@2x")] {
                let px = base * scale
                let ctx = render(px)
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

// MARK: Generated tile

/// Settings for the generated tile (Resources/icon-master/icon.json).
struct TileConfig: Decodable {
    /// Transparent cut-out of the artwork, relative to the JSON file.
    var artwork: String
    /// Width of the artwork's visible bounds as a fraction of the tile width.
    var artworkScale: Double = 0.74
    /// Extra shift after centring on visual weight, as fractions of the tile (x right, y down).
    var artworkOffset: [Double] = [0, 0]
    /// 0 = flat white tile; 1 = white → TileIcon.gradientEnd (light grey).
    var gradientStrength: Double = 0.5
    /// Optional coloured tile: two sRGB hex colours, top left → bottom right (e.g. ["#5AB4F5", "#1E5FC8"]).
    /// When set it replaces the white → light-grey gradient and `gradientStrength` is ignored.
    var tileGradient: [String]? = nil
    /// Opacity of the soft neutral contact shadow under the artwork (drawn on the tile).
    var contactShadow: Double = 0.16

    private enum CodingKeys: String, CodingKey {
        case artwork, artworkScale, artworkOffset, gradientStrength, tileGradient, contactShadow
    }

    /// Every key but `artwork` is optional and falls back to the defaults above.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        artwork = try c.decode(String.self, forKey: .artwork)
        artworkScale = try c.decodeIfPresent(Double.self, forKey: .artworkScale) ?? artworkScale
        artworkOffset = try c.decodeIfPresent([Double].self, forKey: .artworkOffset) ?? artworkOffset
        gradientStrength = try c.decodeIfPresent(Double.self, forKey: .gradientStrength) ?? gradientStrength
        tileGradient = try c.decodeIfPresent([String].self, forKey: .tileGradient)
        contactShadow = try c.decodeIfPresent(Double.self, forKey: .contactShadow) ?? contactShadow
    }
}

/// The owner's artwork on ShotZ's generated macOS tile.
struct TileIcon {
    static let canvas: CGFloat = 1024
    static let tileRect = CGRect(x: 100, y: 100, width: 824, height: 824)   // macOS icon grid
    static let cornerRadius: CGFloat = 185.4                                 // continuous corners
    static let gradientEnd = (r: 0.855, g: 0.865, b: 0.885)                  // a cool light grey

    let config: TileConfig
    let art: CGImage            // trimmed to its visible bounds
    let weightCentre: CGPoint   // visual-weight centre, fractions of `art` (from top left)

    init(configPath: String) {
        let url = URL(filePath: configPath)
        guard let data = try? Data(contentsOf: url) else { fail("tile config: can't read \(configPath)") }
        let config: TileConfig
        do { config = try JSONDecoder().decode(TileConfig.self, from: data) } catch {
            fail("tile config: \(configPath) is not valid: \(error.localizedDescription)")
        }
        guard (0.3...0.95).contains(config.artworkScale) else { fail("tile config: artworkScale must be between 0.3 and 0.95") }
        guard config.artworkOffset.count == 2 else { fail("tile config: artworkOffset must be [x, y]") }
        guard (0...1).contains(config.gradientStrength) else { fail("tile config: gradientStrength must be between 0 and 1") }
        guard (0...1).contains(config.contactShadow) else { fail("tile config: contactShadow must be between 0 and 1") }
        if let colours = config.tileGradient {
            guard colours.count == 2, colours.allSatisfy({ Self.colour(hex: $0) != nil }) else {
                fail("tile config: tileGradient must be two colours like [\"#5AB4F5\", \"#1E5FC8\"]")
            }
        }
        self.config = config

        let artPath = url.deletingLastPathComponent().appending(path: config.artwork).path
        guard case .raster(let full) = Artwork.load(artPath, role: "artwork", minimumPixels: 0, requireSquare: false) else {
            fail("tile config: the artwork must be a transparent PNG")
        }
        let full8 = Self.rgba8(full)
        guard let bounds = alphaBounds(full8, threshold: 127) else { fail("artwork: \(artPath) is fully transparent") }
        let (alpha, _, _) = alphaPlane(full8)
        if alpha.allSatisfy({ $0 == 255 }) { fail("artwork: \(artPath) has no transparency; it must be a cut-out") }
        // Trim to the visible bounds (CGImage cropping counts rows from the top).
        let h = CGFloat(full.height)
        let crop = CGRect(x: bounds.minX, y: h - bounds.maxY, width: bounds.width, height: bounds.height)
        art = full8.makeImage()!.cropping(to: crop.insetBy(dx: -2, dy: -2).intersection(CGRect(x: 0, y: 0, width: full.width, height: full.height)))!
        weightCentre = Self.visualWeightCentre(art)
        note(String(format: "artwork %d×%d px visible; visual-weight centre at %.1f%% × %.1f%% of it",
                    Int(bounds.width), Int(bounds.height), weightCentre.x * 100, weightCentre.y * 100))
    }

    private static func rgba8(_ image: CGImage) -> CGContext {
        let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return ctx
    }

    /// Centre of visual weight: each pixel weighs its opacity × its contrast against a light tile
    /// (darker and more saturated pixels weigh more). Fractions of the image, from the top left.
    private static func visualWeightCentre(_ image: CGImage) -> CGPoint {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        var sx = 0.0, sy = 0.0, sw = 0.0
        for y in 0..<h {
            for x in 0..<w {
                let i = (y * w + x) * 4
                let a = Double(px[i + 3]) / 255
                guard a > 0 else { continue }
                let r = Double(px[i]) / 255 / a, g = Double(px[i + 1]) / 255 / a, b = Double(px[i + 2]) / 255 / a
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let weight = a * ((1 - luminance) + 0.5 * (max(r, g, b) - min(r, g, b)))
                sx += Double(x) * weight; sy += Double(y) * weight; sw += weight
            }
        }
        return CGPoint(x: (sx / sw + 0.5) / Double(w), y: (sy / sw + 0.5) / Double(h))
    }

    static func tilePath(scale k: CGFloat) -> CGPath {
        let rect = CGRect(x: tileRect.minX * k, y: tileRect.minY * k, width: tileRect.width * k, height: tileRect.height * k)
        return RoundedRectangle(cornerRadius: cornerRadius * k, style: .continuous).path(in: rect).cgPath
    }

    /// Where the artwork goes on the 1024 canvas (CoreGraphics coordinates, origin bottom left).
    var artRect: CGRect {
        let tile = Self.tileRect
        let width = tile.width * config.artworkScale
        let height = width * CGFloat(art.height) / CGFloat(art.width)
        let centreX = tile.midX + tile.width * config.artworkOffset[0]
        let centreY = tile.midY - tile.height * config.artworkOffset[1]   // offset y is downward
        let minX = centreX - weightCentre.x * width
        let maxY = centreY + weightCentre.y * height
        return CGRect(x: minX, y: maxY - height, width: width, height: height)
    }

    func render(_ px: Int, dev: Bool) -> CGContext {
        let k = CGFloat(px) / Self.canvas
        let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                            space: srgb, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let path = Self.tilePath(scale: k)
        let tile = path.boundingBoxOfPath
        let (start, end) = tileColours

        // The usual soft drop shadow under the tile.
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -10 * k), blur: 20 * k, color: CGColor(gray: 0, alpha: 0.28))
        ctx.addPath(path)
        ctx.setFillColor(end)
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(path)
        ctx.clip()
        let gradient = CGGradient(colorsSpace: srgb, colors: [start, end] as CFArray, locations: [0, 1])!
        ctx.drawLinearGradient(gradient, start: CGPoint(x: tile.minX, y: tile.maxY), end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

        // Artwork with one soft neutral contact shadow, drawn on the tile (not baked into the art).
        let r = artRect
        let rect = CGRect(x: r.minX * k, y: r.minY * k, width: r.width * k, height: r.height * k)
        let scaled = downsample(art, width: max(1, Int(rect.width.rounded())), height: max(1, Int(rect.height.rounded())))
        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8 * k), blur: 24 * k, color: CGColor(gray: 0, alpha: config.contactShadow))
        ctx.interpolationQuality = .high
        ctx.draw(scaled, in: rect)
        ctx.restoreGState()

        if dev { addDevBand(ctx, px: px, art: tile, clip: path) }

        // Hairline inner edge (at least half a pixel): dark on a light tile so it reads on a light
        // Dock, light on a dark tile so it reads on a dark Dock.
        ctx.addPath(path)
        ctx.setStrokeColor(tileIsDark ? CGColor(gray: 1, alpha: 0.14) : CGColor(gray: 0, alpha: 0.10))
        ctx.setLineWidth(max(4 * k, 1))   // the clip keeps the inner half
        ctx.strokePath()
        ctx.restoreGState()
        return ctx
    }

    /// The tile's two gradient colours (top left, bottom right).
    var tileColours: (CGColor, CGColor) {
        if let colours = config.tileGradient, let a = Self.colour(hex: colours[0]), let b = Self.colour(hex: colours[1]) {
            return (a, b)
        }
        let s = config.gradientStrength
        return (CGColor(gray: 1, alpha: 1),
                CGColor(srgbRed: 1 - (1 - Self.gradientEnd.r) * s, green: 1 - (1 - Self.gradientEnd.g) * s,
                        blue: 1 - (1 - Self.gradientEnd.b) * s, alpha: 1))
    }

    /// True when the tile's average luminance is below the middle.
    var tileIsDark: Bool {
        let (a, b) = tileColours
        func luminance(_ c: CGColor) -> CGFloat {
            let p = c.converted(to: srgb, intent: .defaultIntent, options: nil)?.components ?? [1, 1, 1, 1]
            return p.count >= 3 ? 0.2126 * p[0] + 0.7152 * p[1] + 0.0722 * p[2] : p[0]
        }
        return (luminance(a) + luminance(b)) / 2 < 0.5
    }

    static func colour(hex: String) -> CGColor? {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return CGColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                       blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    /// Notes on fit: the artwork should stay inside the tile's safe area.
    func describeFit() {
        let tile = Self.tileRect.insetBy(dx: Self.tileRect.width * 0.06, dy: Self.tileRect.height * 0.06)
        let r = artRect
        note(String(format: "artwork %.0f×%.0f px on the 1024 canvas (%.0f%% of the tile width), at x %.0f…%.0f, y %.0f…%.0f",
                    r.width, r.height, config.artworkScale * 100, r.minX, r.maxX, Self.canvas - r.maxY, Self.canvas - r.minY))
        if !tile.contains(r) { note("artwork comes within 6% of the tile edge; consider a smaller artworkScale") }
        let source = CGFloat(art.width), target = r.width
        note(String(format: "artwork source is %.0f px wide for %.0f px at 1024 (%.2f× downsampling)%@",
                    source, target, source / target, source < target ? ": upscaled, expect softness" : ""))
    }
}

func writePreviews(to dir: URL, render: (Int, Bool) -> CGContext) {
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    for px in [1024, 128, 64, 32, 16] {
        for dev in [false, true] {
            let name = "AppIcon\(dev ? "-Dev" : "")-\(px).png"
            do { try png(render(px, dev)).write(to: dir.appending(path: name)) } catch { fail("writing \(name): \(error.localizedDescription)") }
        }
    }
    note("wrote previews to \(dir.path)")
}

// MARK: Run

try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
if let tileConfigPath {
    let icon = TileIcon(configPath: tileConfigPath)
    icon.describeFit()
    writeIcns(to: outDir.appending(path: "AppIcon.icns")) { icon.render($0, dev: false) }
    writeIcns(to: outDir.appending(path: "AppIcon-Dev.icns")) { icon.render($0, dev: true) }
    if let previewPath { writePreviews(to: URL(filePath: previewPath, directoryHint: .isDirectory)) { icon.render($0, dev: $1) } }
}
if let masterPath {
    let art = Artwork.load(masterPath, role: "master", minimumPixels: 1024)
    describeShape(art)
    writeIcns(art, dev: false, to: outDir.appending(path: "AppIcon.icns"))
    writeIcns(art, dev: true, to: outDir.appending(path: "AppIcon-Dev.icns"))
    if let previewPath {
        writePreviews(to: URL(filePath: previewPath, directoryHint: .isDirectory)) { px, dev in
            let ctx = art.bitmap(px)
            if dev, let bounds = alphaBounds(ctx) { addDevBand(ctx, px: px, art: bounds) }
            return ctx
        }
    }
}
if let glyphPath {
    guard let glyphSwiftPath else { fail("--glyph needs --glyph-swift <file>") }
    let art = Artwork.load(glyphPath, role: "glyph", minimumPixels: 36)
    writeGlyphSwift(art, to: URL(filePath: glyphSwiftPath))
}
