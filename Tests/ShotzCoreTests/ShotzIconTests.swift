import AppKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ShotzCore

struct ShotzIconTests {
    static let repoRoot = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    @Test func everyPhosphorGlyphParses() throws {
        #expect(!PhosphorGlyphs.pathData.isEmpty)
        for (name, data) in PhosphorGlyphs.pathData {
            let p = try SVGPath.parse(data)
            let b = p.boundingBoxOfPath
            #expect(!p.isEmpty && b.minX >= -0.5 && b.minY >= -0.5 && b.maxX <= 256.5 && b.maxY <= 256.5, "\(name): \(b)")
        }
    }

    @Test func vendoredSetMatchesTheEnum() throws {
        let used = Set(ShotzIcon.allCases.compactMap(\.phosphorName))
        #expect(used == Set(PhosphorGlyphs.pathData.keys))
        let listed = try String(contentsOf: Self.repoRoot.appending(path: "ThirdParty/phosphor/icons.txt"), encoding: .utf8)
            .split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("#") }
        #expect(Set(listed) == used)
        for name in used {
            #expect(FileManager.default.fileExists(atPath: Self.repoRoot.appending(path: "ThirdParty/phosphor/regular/\(name).svg").path()), "\(name)")
        }
        let notices = try String(contentsOf: Self.repoRoot.appending(path: "THIRD-PARTY-NOTICES"), encoding: .utf8)
        let license = try String(contentsOf: Self.repoRoot.appending(path: "ThirdParty/phosphor/LICENSE"), encoding: .utf8)
        #expect(notices.contains(license.trimmingCharacters(in: .whitespacesAndNewlines)))
        for name in used { #expect(notices.contains(name)) }
    }

    @Test(arguments: ShotzIcon.allCases) func iconGeometry(_ icon: ShotzIcon) {
        let rect = CGRect(x: 10, y: 20, width: 32, height: 32)
        let path = icon.path(in: rect)
        #expect(!path.isEmpty, "\(icon) is empty")
        let b = path.boundingBoxOfPath
        #expect(rect.insetBy(dx: -0.01, dy: -0.01).contains(b), "\(icon) spills: \(b)")
        // Reasonable optical size: uses at least half the box in its larger dimension.
        #expect(max(b.width, b.height) >= rect.width * 0.5, "\(icon) is tiny: \(b)")
        #expect(!icon.accessibilityDescription.isEmpty)
        // y-up and flipped placements mirror each other within the rect.
        let f = icon.path(in: rect, flipped: true).boundingBoxOfPath
        #expect(abs((f.minY - rect.minY) - (rect.maxY - b.maxY)) < 0.01)
    }

    @Test func descriptionsAreUnique() {
        let all = ShotzIcon.allCases.map(\.accessibilityDescription)
        #expect(Set(all).count == all.count)
    }

    @Test func templateImageIsCrispAtTwoX() throws {
        let image = ShotzIcon.arrowTool.image(pointSize: 18)
        #expect(image.isTemplate && image.size == NSSize(width: 18, height: 18))
        #expect(image.accessibilityDescription == ShotzIcon.arrowTool.accessibilityDescription)
        // Rendered at 2× it draws real vector detail (many partially covered pixels, not a blurry upscale).
        let rep = try #require(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 36, pixelsHigh: 36, bitsPerSample: 8, samplesPerPixel: 4,
                                                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        rep.size = NSSize(width: 18, height: 18)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: 18, height: 18))
        NSGraphicsContext.restoreGraphicsState()
        var opaque = 0
        for y in 0..<36 { for x in 0..<36 where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.9 { opaque += 1 } }
        #expect(opaque > 60)
    }

    /// SHOTZ_ICON_SHEET=<dir> writes icons-contact-sheet.png: every icon at 16, 20 and 32 pt
    /// (rendered at 2×) on light and dark backgrounds.
    @Test func contactSheet() throws {
        guard let dir = ProcessInfo.processInfo.environment["SHOTZ_ICON_SHEET"] else { return }
        try IconSheet.write(ShotzIcon.allCases, to: URL(filePath: dir).appending(path: "icons-contact-sheet.png"))
    }
}

/// Contact-sheet rendering for visual review.
enum IconSheet {
    static func write(_ icons: [ShotzIcon], to url: URL, scale: CGFloat = 2) throws {
        let columns = 2, rowH: CGFloat = 46, nameW: CGFloat = 170, half: CGFloat = 150
        let colW = nameW + 2 * half + 20
        let rows = Int((Double(icons.count) / Double(columns)).rounded(.up))
        let W = CGFloat(columns) * colW, H = CGFloat(rows) * rowH + 30
        let ctx = CGContext(data: nil, width: Int(W * scale), height: Int(H * scale), bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.scaleBy(x: scale, y: scale)
        ctx.translateBy(x: 0, y: H)
        ctx.scaleBy(x: 1, y: -1) // top-left space
        ctx.setFillColor(CGColor(gray: 1, alpha: 1)); ctx.fill(CGRect(x: 0, y: 0, width: W, height: H))
        let light = CGColor(srgbRed: 0.96, green: 0.96, blue: 0.97, alpha: 1), dark = CGColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1)
        for c in 0..<columns {
            let x0 = CGFloat(c) * colW
            ctx.setFillColor(light); ctx.fill(CGRect(x: x0 + nameW, y: 0, width: half, height: H))
            ctx.setFillColor(dark); ctx.fill(CGRect(x: x0 + nameW + half, y: 0, width: half, height: H))
            label("16  20  32 pt", at: CGPoint(x: x0 + nameW + 8, y: 8), in: ctx)
        }
        for (i, icon) in icons.enumerated() {
            let c = i / rows, r = i % rows
            let x0 = CGFloat(c) * colW, y0 = 30 + CGFloat(r) * rowH
            label(icon.rawValue + (icon.phosphorName.map { "  (\($0))" } ?? "  ★"), at: CGPoint(x: x0 + 6, y: y0 + 16), in: ctx)
            for (bg, color) in [(CGFloat(0), CGColor(gray: 0.1, alpha: 1)), (half, CGColor(gray: 0.95, alpha: 1))] {
                var x = x0 + nameW + bg + 10
                for size in [CGFloat(16), 20, 32] {
                    // Snap to whole points like AppKit places images.
                    let rect = CGRect(x: x.rounded(), y: (y0 + (rowH - size) / 2).rounded(), width: size, height: size)
                    icon.draw(in: ctx, rect: rect, color: color, flipped: true)
                    x += size + 16
                }
            }
        }
        let image = ctx.makeImage()!
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CocoaError(.fileWriteUnknown) }
    }

    private static func label(_ s: String, at p: CGPoint, in ctx: CGContext) {
        let attrs: [CFString: Any] = [kCTFontAttributeName: CTFontCreateWithName("Helvetica" as CFString, 11, nil),
                                      kCTForegroundColorAttributeName: CGColor(gray: 0.35, alpha: 1)]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
        ctx.saveGState()
        ctx.translateBy(x: p.x, y: p.y + 10)
        ctx.scaleBy(x: 1, y: -1)
        ctx.textPosition = .zero
        CTLineDraw(line, ctx)
        ctx.restoreGState()
    }
}
