import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AnnotationKit

/// Golden-image tests: each case renders a small document and compares it with a checked-in
/// PNG under Goldens/ with a per-channel tolerance (antialiasing and font rasterisation can
/// shift slightly between macOS versions).
///
/// Record or refresh: `SHOTZ_RECORD_GOLDENS=1 swift test --filter GoldenTests`, then inspect
/// the PNGs before committing. Missing goldens fail the test (they are never auto-recorded).
struct GoldenTests {
    static let directory = URL(filePath: #filePath).deletingLastPathComponent().appending(path: "Goldens")
    static let recording = ProcessInfo.processInfo.environment["SHOTZ_RECORD_GOLDENS"] == "1"
    static let size = CGSize(width: 240, height: 140)
    /// Max difference per channel (0–255) before a pixel counts as different.
    static let channelTolerance = 24
    /// Fraction of pixels allowed to differ beyond the tolerance.
    static let allowedFraction = 0.004

    struct Case: CustomTestStringConvertible, Sendable {
        let name: String
        let objects: [AnnotationObject]
        var background: BackgroundStyle?
        var testDescription: String { name }
    }

    static let cases: [Case] = {
        var out: [Case] = []
        func style(_ body: (inout ObjectStyle) -> Void = { _ in }) -> ObjectStyle {
            var s = ObjectStyle(color: .red, lineWidth: 5, fontSize: 18)
            body(&s)
            return s
        }
        for a in ArrowStyle.allCases {
            for outline in [false, true] {
                let g = ArrowGeometry(start: CGPoint(x: 30, y: 115), end: CGPoint(x: 205, y: 30),
                                      control: a == .curved ? CGPoint(x: 70, y: 40) : nil, style: a)
                out.append(Case(name: "arrow-\(a.rawValue)\(outline ? "-outline" : "")",
                                objects: [AnnotationObject(shape: .arrow(g), style: style { $0.contrastOutline = outline; $0.color = outline ? .yellow : .red })]))
            }
        }
        for fill in ObjectStyle.FillMode.allCases {
            out.append(Case(name: "rect-\(fill.rawValue)", objects: [
                AnnotationObject(shape: .rectangle(CGRect(x: 30, y: 25, width: 180, height: 90), cornerRadius: fill == .outline ? 0 : 16),
                                 style: style { $0.fill = fill; $0.color = .blue }),
            ]))
            out.append(Case(name: "ellipse-\(fill.rawValue)", objects: [
                AnnotationObject(shape: .ellipse(CGRect(x: 30, y: 25, width: 180, height: 90)), style: style { $0.fill = fill; $0.color = .purple }),
            ]))
        }
        out.append(Case(name: "rect-dashed-translucent", objects: [
            AnnotationObject(shape: .rectangle(CGRect(x: 30, y: 25, width: 180, height: 90), cornerRadius: 6),
                             style: style { $0.dash = .dashed; $0.opacity = 0.6 }),
        ]))
        for dash in ObjectStyle.Dash.allCases {
            out.append(Case(name: "line-\(dash.rawValue)", objects: [
                AnnotationObject(shape: .line(start: CGPoint(x: 20, y: 120), end: CGPoint(x: 220, y: 20)), style: style { $0.dash = dash; $0.color = .black }),
            ]))
        }
        for d in TextStyle.Decoration.allCases {
            out.append(Case(name: "text-\(d.rawValue)", objects: [
                AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 16, y: 20), string: "Shotz 42 ✓", style: TextStyle(decoration: d))),
                                 style: style { $0.color = d == .outlined ? .white : .red }),
                AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 16, y: 66), wrapWidth: 150, string: "Bold centred wrapping text",
                                                      style: TextStyle(decoration: d, isBold: true, alignment: .center))),
                                 style: style { $0.color = .blue; $0.fontSize = 15 }),
            ]))
        }
        out.append(Case(name: "highlight", objects: [
            AnnotationObject(shape: .highlight(.rect(CGRect(x: 10, y: 95, width: 200, height: 24))), style: style { $0.color = .yellow }),
            AnnotationObject(shape: .highlight(.rect(CGRect(x: 120, y: 88, width: 110, height: 10))), style: style { $0.color = .yellow }),
            AnnotationObject(shape: .highlight(.freehand([CGPoint(x: 20, y: 20), CGPoint(x: 80, y: 40), CGPoint(x: 150, y: 25), CGPoint(x: 220, y: 45)])),
                             style: style { $0.color = .green; $0.lineWidth = 16 }),
        ]))
        out.append(Case(name: "counters", objects: [
            AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 40, y: 40), value: 1)), style: style { $0.fontSize = 16 }),
            AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 100, y: 40), value: 2, numbering: .alphabetic)),
                             style: style { $0.fontSize = 16; $0.color = .yellow }),
            AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 160, y: 40), value: 12)), style: style { $0.fontSize = 16; $0.color = .white }),
            AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 60, y: 100), tail: CGPoint(x: 140, y: 130), value: 3)),
                             style: style { $0.fontSize = 16; $0.color = .blue }),
        ]))
        out.append(Case(name: "pen", objects: [
            AnnotationObject(shape: .pen(StrokeSmoothing.smooth((0...40).map { i -> CGPoint in
                let t = CGFloat(i)
                return CGPoint(x: 20 + t * 5, y: 70 + sin(t / 4) * 40)
            })), style: style { $0.color = .orange }),
        ]))
        for kind in RedactMode.Kind.allCases {
            out.append(Case(name: "redact-\(kind.rawValue)", objects: [
                // A box overlapping the left part: drawn above the redaction, never sampled by it.
                AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 84, width: 40, height: 56), cornerRadius: 0), style: style { $0.fill = .filled; $0.color = .green }),
                AnnotationObject(shape: .redact(CGRect(x: 8, y: 98, width: 220, height: 40), RedactMode(kind: kind)), style: style { $0.color = .black }),
            ]))
        }
        out.append(Case(name: "background-gradient", objects: [
            AnnotationObject(shape: .arrow(ArrowGeometry(start: CGPoint(x: 40, y: 110), end: CGPoint(x: 190, y: 40))), style: style()),
        ], background: BackgroundStyle(fill: .gradient(GradientPreset.all[2].fill), padding: 0.1, cornerRadius: 12, shadow: .soft, alignment: .center, aspect: .square)))
        out.append(Case(name: "background-strong-shadow", objects: [], background: BackgroundStyle(fill: .solid(.white), padding: 0.15, cornerRadius: 8, shadow: .strong)))
        return out
    }()

    static func render(_ c: Case) throws -> CGImage {
        // A small text-bearing base so redactions have something to hide; scale 1 keeps blocks small.
        let base = BaseImageProvider(image: TestImages.base(width: Int(size.width), height: Int(size.height)), url: URL(filePath: "/golden"))
        let doc = AnnotationDocument(baseImageURL: base.url, pixelSize: size, scale: 1, objects: c.objects, background: c.background)
        return try AnnotationRenderer.renderImage(doc, base: base, outputScale: 2)
    }

    @Test(arguments: cases) func matchesGolden(_ c: Case) throws {
        let image = try Self.render(c)
        let url = Self.directory.appending(path: "\(c.name).png")
        if Self.recording {
            try TestImages.writePNG(image, to: url)
            return
        }
        let src = try #require(CGImageSourceCreateWithURL(url as CFURL, nil), "missing golden \(c.name).png; record with SHOTZ_RECORD_GOLDENS=1")
        let golden = try #require(CGImageSourceCreateImageAtIndex(src, 0, nil))
        #expect(golden.width == image.width && golden.height == image.height)
        let a = Pixels(image), b = Pixels(golden)
        guard a.data.count == b.data.count else { return }
        var differing = 0
        for i in stride(from: 0, to: a.data.count, by: 4) {
            for ch in 0..<4 where abs(Int(a.data[i + ch]) - Int(b.data[i + ch])) > Self.channelTolerance {
                differing += 1
                break
            }
        }
        let fraction = Double(differing) / Double(a.width * a.height)
        #expect(fraction <= Self.allowedFraction, "\(c.name): \(differing) pixels differ (\(fraction))")
    }
}
