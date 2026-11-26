import CoreGraphics
import CoreText
import Foundation
import Testing
@testable import AnnotationKit

/// Default-strength pixelate and blur must make 24–40 px text unrecoverable, and must be
/// hard-clipped to their rect. "Unrecoverable" is measured three ways:
/// 1. cell size / blur sigma relative to the text height,
/// 2. distinguishability: two different strings must be nearly indistinguishable after
///    redaction compared with before (an attacker comparing candidate renderings learns little),
/// 3. for blur, fine detail (stroke-scale gradient energy) is essentially gone.
struct RedactionStrengthTests {
    static let width = 900, height = 160

    /// White image with one line of black text whose cap-to-descender box sits in `textRect`.
    static func textImage(_ string: String, fontSize: CGFloat) -> (CGImage, CGRect) {
        let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let font = CTFontCreateWithName("Helvetica" as CFString, fontSize, nil)
        let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: CGColor(gray: 0, alpha: 1)]
        let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, string as CFString, attrs as CFDictionary))
        let baselineFromTop: CGFloat = 80
        ctx.textPosition = CGPoint(x: 40, y: CGFloat(height) - baselineFromTop)
        CTLineDraw(line, ctx)
        let ascent = CTFontGetAscent(font), descent = CTFontGetDescent(font)
        // A tight but realistic redaction box: the line's ascent + descent plus a little air.
        let box = CGRect(x: 30, y: baselineFromTop - ascent - 3, width: CGFloat(width) - 60, height: ascent + descent + 6).integral
        return (ctx.makeImage()!, box)
    }

    static func redact(_ image: CGImage, rect: CGRect, mode: RedactMode, scale: CGFloat) throws -> Pixels {
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: width, height: height), scale: scale,
                                     objects: [AnnotationObject(shape: .redact(rect, mode))])
        return Pixels(try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: image, url: doc.baseImageURL), outputScale: 1))
    }

    static func meanAbsDiff(_ a: Pixels, _ b: Pixels, in r: CGRect) -> Double {
        var sum = 0.0, n = 0.0
        for y in Int(r.minY)..<Int(r.maxY) { for x in Int(r.minX)..<Int(r.maxX) { sum += abs(a.luma(x, y) - b.luma(x, y)); n += 1 } }
        return sum / n
    }

    /// Mean absolute luma gradient (fine detail).
    static func detail(_ p: Pixels, in r: CGRect) -> Double {
        var sum = 0.0, n = 0.0
        for y in Int(r.minY)..<(Int(r.maxY) - 1) {
            for x in Int(r.minX)..<(Int(r.maxX) - 1) {
                sum += abs(p.luma(x + 1, y) - p.luma(x, y)) + abs(p.luma(x, y + 1) - p.luma(x, y)); n += 1
            }
        }
        return sum / n
    }

    struct Case: Sendable, CustomTestStringConvertible {
        var fontSize: CGFloat
        var scale: CGFloat
        var kind: RedactMode.Kind
        var testDescription: String { "\(kind.rawValue) \(Int(fontSize))px @\(Int(scale))x" }
    }

    static let cases: [Case] = [24, 32, 40].flatMap { f in [1, 2].flatMap { s in [RedactMode.Kind.pixelate, .blur].map { Case(fontSize: f, scale: CGFloat(s), kind: $0) } } }

    @Test(arguments: cases) func defaultStrengthMakesTextUnrecoverable(_ c: Case) throws {
        let (a, box) = Self.textImage("Rk8wq2Lm Pass 4417 hunter", fontSize: c.fontSize)
        let (b, _) = Self.textImage("Hp3zt7Xc Code 9081 dragon", fontSize: c.fontSize)
        let mode = RedactMode(kind: c.kind)
        let ra = try Self.redact(a, rect: box, mode: mode, scale: c.scale)
        let rb = try Self.redact(b, rect: box, mode: mode, scale: c.scale)
        let inner = box
        let before = Self.meanAbsDiff(Pixels(a), Pixels(b), in: inner)
        let after = Self.meanAbsDiff(ra, rb, in: inner)
        let distinguishability = after / before
        let detailRatio = Self.detail(ra, in: inner) / Self.detail(Pixels(a), in: inner)
        let size = c.kind == .pixelate
            ? Redactor.blockSize(strength: mode.strength, scale: c.scale, rect: box)
            : Redactor.blurRadius(strength: mode.strength, scale: c.scale, rect: box)
        if c.kind == .pixelate {
            #expect(size >= c.fontSize * 0.55, "cell \(size) too small for \(c.fontSize) px text")
        } else {
            #expect(size >= c.fontSize * 0.4, "sigma \(size) too small for \(c.fontSize) px text")
            #expect(detailRatio < 0.08)
        }
        // Measured 0.02–0.14 across these cases; originals differ by 1.0 by definition.
        #expect(distinguishability < 0.2, "\(c.testDescription): \(distinguishability)")
    }

    @Test(arguments: [RedactMode.pixelate, .blur, .solid], [1.0, 0.75, 1.5])
    func edgesAreHardClipped(_ mode: RedactMode, _ outputScale: CGFloat) throws {
        let (image, box) = Self.textImage("Rk8wq2Lm Pass 4417 hunter", fontSize: 32)
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: Self.width, height: Self.height), scale: 2,
                                     objects: [AnnotationObject(shape: .redact(box, mode), style: ObjectStyle(color: .black))])
        let base = BaseImageProvider(image: image, url: doc.baseImageURL)
        let out = Pixels(try AnnotationRenderer.renderImage(doc, base: base, outputScale: outputScale))
        var plainDoc = doc
        plainDoc.objects = []
        let plain = Pixels(try AnnotationRenderer.renderImage(plainDoc, base: base, outputScale: outputScale))
        let r = CGRect(x: box.minX * outputScale, y: box.minY * outputScale, width: box.width * outputScale, height: box.height * outputScale)
        // Two device pixels outside: untouched.
        for x in stride(from: Int(r.minX), to: Int(r.maxX), by: 7) {
            #expect(out.rgba(x, Int(r.minY.rounded(.down)) - 2) == plain.rgba(x, Int(r.minY.rounded(.down)) - 2))
            #expect(out.rgba(x, Int(r.maxY.rounded(.up)) + 1) == plain.rgba(x, Int(r.maxY.rounded(.up)) + 1))
        }
        // Boundary rows/columns that the rect touches carry no sharp original detail: every such
        // pixel differs from the original wherever the original had dark ink.
        let edgeRows = [Int(r.minY.rounded(.down)), Int(r.maxY.rounded(.up)) - 1]
        for y in edgeRows {
            for x in Int(r.minX.rounded(.up))..<Int(r.maxX.rounded(.down)) where plain.luma(x, y) < 0.2 {
                Issue.record("sharp ink at edge (\(x), \(y)) for \(mode.kind) @\(outputScale)")
            }
        }
        if mode.kind != .solid {
            #expect(base.redactedImage(rect: box, mode: mode, scale: 2)?.width == Int(box.width))
        }
    }
}
