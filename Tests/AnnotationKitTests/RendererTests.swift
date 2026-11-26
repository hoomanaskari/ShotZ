import CoreGraphics
import Foundation
import ImageIO
import ShotzCore
import Testing
@testable import AnnotationKit

struct RendererTests {
    static let size = CGSize(width: 600, height: 400)

    /// Draws one object alone onto a transparent canvas (top-left space) and returns the RGBA bytes.
    static func renderAlone(_ object: AnnotationObject, size: CGSize = size) -> (ctx: CGContext, bytes: UnsafeMutablePointer<UInt8>) {
        let ctx = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: Int(size.width) * 4,
                            space: TestImages.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: size.height)
        ctx.scaleBy(x: 1, y: -1)
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: size, scale: 2, objects: [object])
        let base = BaseImageProvider(image: TestImages.base(width: Int(size.width), height: Int(size.height)), url: doc.baseImageURL)
        AnnotationRenderer.draw(object, in: ctx, document: doc, base: base)
        return (ctx, ctx.data!.bindMemory(to: UInt8.self, capacity: Int(size.width * size.height) * 4))
    }

    static let boundsCases: [AnnotationObject] = {
        let s = ObjectStyle(color: .blue, lineWidth: 9, fontSize: 30, contrastOutline: true)
        var objects: [AnnotationObject] = ArrowStyle.allCases.map {
            AnnotationObject(shape: .arrow(ArrowGeometry(start: CGPoint(x: 120, y: 300), end: CGPoint(x: 420, y: 90),
                                                         control: CGPoint(x: 160, y: 120), style: $0)), style: s)
        }
        objects += [
            AnnotationObject(shape: .rectangle(CGRect(x: 100, y: 100, width: 200, height: 120), cornerRadius: 20), style: s),
            AnnotationObject(shape: .ellipse(CGRect(x: 100, y: 100, width: 200, height: 120)), style: s),
            AnnotationObject(shape: .line(start: CGPoint(x: 50, y: 50), end: CGPoint(x: 400, y: 300)), style: s),
            AnnotationObject(shape: .pen([CGPoint(x: 50, y: 300), CGPoint(x: 150, y: 80), CGPoint(x: 250, y: 330), CGPoint(x: 350, y: 60)]), style: s),
            AnnotationObject(shape: .highlight(.freehand([CGPoint(x: 50, y: 200), CGPoint(x: 300, y: 220)])), style: s),
            AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 200, y: 200), tail: CGPoint(x: 330, y: 330), value: 7)), style: s),
        ]
        for d in TextStyle.Decoration.allCases {
            objects.append(AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 60, y: 120), wrapWidth: d == .solidPill ? 260 : nil,
                                                                 string: "Hello Shotz 👋\nSecond line", style: TextStyle(decoration: d, isBold: true))),
                                            style: s))
        }
        return objects
    }()

    @Test(arguments: boundsCases) func boundsContainEveryDrawnPixel(_ object: AnnotationObject) {
        let (ctx, bytes) = Self.renderAlone(object)
        defer { withExtendedLifetime(ctx) {} } // bytes point into the context's buffer
        let b = AnnotationRenderer.bounds(of: object)
        var outside = 0, inked = 0
        for y in 0..<Int(Self.size.height) {
            for x in 0..<Int(Self.size.width) where bytes[(y * Int(Self.size.width) + x) * 4 + 3] > 2 {
                inked += 1
                if !b.contains(CGPoint(x: CGFloat(x) + 0.5, y: CGFloat(y) + 0.5)) { outside += 1 }
            }
        }
        #expect(inked > 100, "\(object.kind) drew nothing")
        #expect(outside == 0, "\(object.kind): \(outside) pixels outside \(b)")
    }

    @Test func redactionUsesBaseImageOnlyAndIsStrong() throws {
        let size = CGSize(width: 600, height: 400)
        let baseImage = TestImages.base(width: 600, height: 400)
        let rect = CGRect(x: 10, y: 310, width: 500, height: 80) // over the sample text
        // A bright magenta box under and over the redaction must never bleed into its pixels.
        let magenta = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 300, width: 600, height: 100), cornerRadius: 0),
                                       style: ObjectStyle(color: RGBAColor(red: 1, green: 0, blue: 1), fill: .filled, contrastOutline: false))
        for mode in [RedactMode.pixelate, .blur] {
            let redact = AnnotationObject(shape: .redact(rect, mode))
            let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: size, scale: 2, objects: [redact])
            let base = BaseImageProvider(image: baseImage, url: doc.baseImageURL)
            let out = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1)
            let plain = try AnnotationRenderer.renderImage(AnnotationDocument(baseImageURL: doc.baseImageURL, pixelSize: size), base: base, outputScale: 1)
            // Strength: inside the rect the local contrast of text is gone.
            let redactedRange = Pixels(out).lumaRange(in: rect.insetBy(dx: 20, dy: 10))
            let originalRange = Pixels(plain).lumaRange(in: rect.insetBy(dx: 20, dy: 10))
            #expect(originalRange > 0.6, "test image should have text there")
            #expect(redactedRange < 0.3, "\(mode.kind): range \(redactedRange)")
            // Base-only: the cached redaction is the same whatever annotations exist.
            let cached = try #require(base.redactedImage(rect: rect, mode: mode, scale: 2))
            var withBox = doc
            withBox.objects.insert(magenta, at: 0)
            _ = try AnnotationRenderer.renderImage(withBox, base: base, outputScale: 1)
            #expect(base.redactedImage(rect: rect, mode: mode, scale: 2) === cached)
            #expect(Pixels(cached).maxChroma(in: CGRect(x: 0, y: 0, width: cached.width, height: cached.height)) < 0.4)
        }
    }

    @Test func redactionRendersBeneathLaterObjectsAndSolidIsOpaque() throws {
        let size = CGSize(width: 200, height: 100)
        let red = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 0),
                                   style: ObjectStyle(color: RGBAColor(red: 1, green: 0, blue: 0), fill: .filled))
        let solid = AnnotationObject(shape: .redact(CGRect(x: 0, y: 0, width: 200, height: 100), .solid),
                                     style: ObjectStyle(color: RGBAColor(red: 0, green: 0, blue: 1, alpha: 0.2), opacity: 0.1))
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: size, objects: [red, solid])
        let out = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: TestImages.base(width: 200, height: 100), url: doc.baseImageURL), outputScale: 1)
        let p = Pixels(out)
        #expect(p.rgba(50, 50) == [255, 0, 0, 255])   // the box stays on top
        #expect(p.rgba(150, 50) == [0, 0, 255, 255])  // solid redaction ignores alpha/opacity
    }

    @Test func previewRedactionCoversTheRect() {
        let size = CGSize(width: 600, height: 400)
        let base = BaseImageProvider(image: TestImages.base(width: 600, height: 400), url: URL(filePath: "/x"))
        let redact = AnnotationObject(shape: .redact(CGRect(x: 10, y: 300, width: 400, height: 80), .pixelate))
        let doc = AnnotationDocument(baseImageURL: base.url, pixelSize: size, scale: 2, objects: [redact])
        let ctx = CGContext(data: nil, width: 600, height: 400, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.translateBy(x: 0, y: 400)
        ctx.scaleBy(x: 1, y: -1)
        AnnotationRenderer.draw(redact, in: ctx, document: doc, base: base, quality: .preview)
        let p = Pixels(ctx.makeImage()!)
        #expect(p.rgba(100, 340)[3] == 255)
        #expect(p.rgba(100, 200)[3] == 0)
        #expect(base.redactedImage(rect: CGRect(x: 10, y: 300, width: 400, height: 80), mode: .pixelate, scale: 2) != nil)
    }

    @Test func backgroundLayout() {
        var doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 1000, height: 500))
        #expect(BackgroundLayout(document: doc).canvasSize == CGSize(width: 1000, height: 500))
        doc.background = BackgroundStyle(padding: 0.1, aspect: .auto)
        var l = BackgroundLayout(document: doc)
        #expect(l.canvasSize == CGSize(width: 1200, height: 700))
        #expect(l.imageFrame == CGRect(x: 100, y: 100, width: 1000, height: 500))
        doc.background?.aspect = .square
        doc.background?.alignment = .bottomRight
        l = BackgroundLayout(document: doc)
        #expect(l.canvasSize == CGSize(width: 1200, height: 1200))
        #expect(l.imageFrame.maxX == 1100 && l.imageFrame.maxY == 1100)
        doc.background?.alignment = .top
        doc.crop = CGRect(x: 100, y: 0, width: 400, height: 400)
        doc.background?.padding = 0.25
        l = BackgroundLayout(document: doc)
        #expect(l.canvasSize == CGSize(width: 600, height: 600))
        #expect(l.imageFrame == CGRect(x: 100, y: 100, width: 400, height: 400))
        // Auto-balance pads around the visible content only.
        doc.background = BackgroundStyle(padding: 0.1, autoBalance: true)
        doc.crop = nil
        l = BackgroundLayout(document: doc, visibleContent: CGRect(x: 50, y: 50, width: 900, height: 400))
        #expect(l.canvasSize == CGSize(width: 1100, height: 600))
        #expect(l.imageFrame.origin == CGPoint(x: 50, y: 50))
    }

    @Test func renderWithBackgroundAndCropAtScale() throws {
        var doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 400, height: 200), crop: CGRect(x: 100, y: 0, width: 200, height: 200))
        doc.background = BackgroundStyle(fill: .solid(RGBAColor(red: 0, green: 1, blue: 0)), padding: 0.1, cornerRadius: 30, shadow: .off)
        let out = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: TestImages.base(width: 400, height: 200), url: doc.baseImageURL), outputScale: 2)
        #expect(out.width == 480 && out.height == 480)
        let p = Pixels(out)
        #expect(p.rgba(4, 4) == [0, 255, 0, 255])       // padding
        #expect(p.rgba(44, 44) == [0, 255, 0, 255])     // rounded-off image corner shows the fill
        #expect(p.rgba(240, 240) != [0, 255, 0, 255])   // image
        for preset in GradientPreset.all {
            doc.background?.fill = .gradient(preset.fill)
            _ = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: TestImages.base(width: 400, height: 200), url: doc.baseImageURL), outputScale: 0.25)
        }
        #expect(GradientPreset.all.count == 12 && Set(GradientPreset.all.map(\.name)).count == 12)
    }

    @Test func keepsSourceColourSpace() throws {
        let p3 = CGColorSpace(name: CGColorSpace.displayP3)!
        let ctx = CGContext(data: nil, width: 64, height: 32, bitsPerComponent: 8, bytesPerRow: 0, space: p3,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 64, height: 32))
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 64, height: 32),
                                     objects: [AnnotationObject(shape: .redact(CGRect(x: 0, y: 0, width: 32, height: 32), .blur))])
        let out = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: ctx.makeImage()!, url: doc.baseImageURL), outputScale: 1)
        #expect(out.colorSpace?.name == CGColorSpace.displayP3)
        // Untouched pixels keep their exact values (no colour conversion round trip).
        let a = Pixels(out).rgba(48, 16), b = Pixels(ctx.makeImage()!).rgba(48, 16)
        #expect(zip(a, b).allSatisfy { abs(Int($0) - Int($1)) <= 1 })
    }

    @Test(arguments: [ImageFormat.png, .jpeg, .heic]) func exportWritesFormatsAtScale(_ format: ImageFormat) throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "shotz-export-\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) } // best-effort cleanup of a temp folder
        let baseURL = dir.appending(path: "base.png")
        try TestImages.writePNG(TestImages.base(width: 300, height: 200), to: baseURL)
        var doc = ShowcaseTests.showcaseDocument(width: 300, height: 200)
        doc.baseImageURL = baseURL
        doc.objects = Array(doc.objects.prefix(5))
        for scale in [1.0, 0.5] {
            let url = dir.appending(path: "out-\(scale).\(format.rawValue)")
            try DocumentExport.write(doc, to: url, format: format, quality: 0.8, scale: scale)
            let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil))
            let props = try #require(CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any])
            #expect(props[kCGImagePropertyPixelWidth] as? Int == Int(300 * scale))
            #expect(props[kCGImagePropertyPixelHeight] as? Int == Int(200 * scale))
            #expect((props[kCGImagePropertyDPIWidth] as? Double).map { abs($0 - 144 * scale) < 1 } ?? false)
        }
        let data = try DocumentExport.data(doc, base: BaseImageProvider(url: baseURL), format: format, quality: 0.8, scale: 1)
        #expect(data.count > 100)
    }

    @Test func jpegIsMattedOntoWhite() throws {
        let clear = CGContext(data: nil, width: 20, height: 20, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.sRGB,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 20, height: 20))
        let out = try DocumentExport.render(doc, base: BaseImageProvider(image: clear, url: doc.baseImageURL), format: .jpeg, scale: 1)
        #expect(Pixels(out).rgba(10, 10) == [255, 255, 255, 255])
    }

    @Test func fiveKExportWithFiftyObjectsIsFast() throws {
        let base = BaseImageProvider(image: TestImages.base(width: 5120, height: 2880), url: URL(filePath: "/x"))
        var doc = ShowcaseTests.showcaseDocument(width: 5120, height: 2880)
        let template = doc.objects
        doc.objects = (0..<50).map { i in
            template[i % template.count].duplicated(offsetBy: CGVector(dx: CGFloat(i % 4) * 600, dy: CGFloat(i / 25) * 1300))
        }
        // Large redactions dominate the cost; include one of each kind at 5K size.
        doc.objects += [
            AnnotationObject(shape: .redact(CGRect(x: 100, y: 1800, width: 1600, height: 500), .pixelate)),
            AnnotationObject(shape: .redact(CGRect(x: 1800, y: 1800, width: 1600, height: 500), .blur)),
            AnnotationObject(shape: .redact(CGRect(x: 3500, y: 1800, width: 1500, height: 500), .solid)),
        ]
        doc.background = BackgroundStyle(fill: .gradient(GradientPreset.all[0].fill), padding: 0.05, shadow: .soft)
        _ = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1) // warm caches (fonts, redactions)
        let clock = ContinuousClock()
        var image: CGImage?
        let cold = try clock.measure {
            base.clearCache()
            image = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1)
        }
        #expect(image?.width == 5632 && image?.height == 3392)
        #expect(cold < .milliseconds(1000), "5K export took \(cold)")
    }
}

/// Reads pixels of a CGImage by redrawing it into a known sRGB RGBA8 layout.
struct Pixels {
    let width: Int, height: Int
    let data: [UInt8]

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        width = w; height = h
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let space = image.colorSpace ?? TestImages.sRGB
        buf.withUnsafeMutableBytes { raw in
            let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: space.model == .rgb ? space : TestImages.sRGB, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        data = buf
    }

    /// Top-left origin.
    func rgba(_ x: Int, _ y: Int) -> [UInt8] {
        let i = (y * width + x) * 4
        return Array(data[i..<(i + 4)])
    }

    func luma(_ x: Int, _ y: Int) -> Double {
        let p = rgba(x, y)
        return (0.2126 * Double(p[0]) + 0.7152 * Double(p[1]) + 0.0722 * Double(p[2])) / 255
    }

    func lumaRange(in rect: CGRect) -> Double {
        var lo = 1.0, hi = 0.0
        for y in Int(rect.minY)..<Int(rect.maxY) { for x in Int(rect.minX)..<Int(rect.maxX) { let l = luma(x, y); lo = min(lo, l); hi = max(hi, l) } }
        return hi - lo
    }

    func maxChroma(in rect: CGRect) -> Double {
        var m = 0.0
        for y in Int(rect.minY)..<Int(rect.maxY) {
            for x in Int(rect.minX)..<Int(rect.maxX) {
                let p = rgba(x, y).prefix(3).map(Double.init)
                m = max(m, ((p.max() ?? 0) - (p.min() ?? 0)) / 255)
            }
        }
        return m
    }
}
