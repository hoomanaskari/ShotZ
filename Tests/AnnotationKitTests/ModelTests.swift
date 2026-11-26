import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

struct ModelTests {
    static let allShapes: [AnnotationObject.Shape] = [
        .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 10), control: CGPoint(x: 5, y: 0), style: .curved)),
        .rectangle(CGRect(x: 1, y: 2, width: 3, height: 4), cornerRadius: 2),
        .ellipse(CGRect(x: 0, y: 0, width: 5, height: 5)),
        .line(start: .zero, end: CGPoint(x: 3, y: 3)),
        .text(TextBox(origin: CGPoint(x: 4, y: 4), wrapWidth: 100, string: "Hi 👋", style: TextStyle(decoration: .solidPill, isBold: true))),
        .highlight(.freehand([.zero, CGPoint(x: 1, y: 1)])),
        .highlight(.rect(CGRect(x: 0, y: 0, width: 9, height: 2))),
        .redact(CGRect(x: 0, y: 0, width: 8, height: 8), .pixelate),
        .counter(CounterGeometry(center: CGPoint(x: 20, y: 20), tail: CGPoint(x: 40, y: 40), value: 3, numbering: .alphabetic)),
        .pen([.zero, CGPoint(x: 2, y: 5)]),
    ]

    @Test func documentCodableRoundTrip() throws {
        let doc = AnnotationDocument(
            baseImageURL: URL(filePath: "/tmp/base.png"),
            pixelSize: CGSize(width: 200, height: 100),
            scale: 2,
            objects: Self.allShapes.map { AnnotationObject(shape: $0, style: ObjectStyle(color: .green, fill: .filled)) },
            crop: CGRect(x: 1, y: 1, width: 50, height: 50),
            background: BackgroundStyle(fill: .gradient(.init(from: .blue, to: .purple)), aspect: .sixteenNine)
        )
        let decoded = try JSONDecoder().decode(AnnotationDocument.self, from: try doc.jsonData())
        #expect(decoded == doc)
    }

    @Test func counterLabels() {
        func label(_ v: Int, _ n: CounterGeometry.Numbering) -> String {
            CounterGeometry(center: .zero, value: v, numbering: n).label
        }
        #expect(label(3, .numeric) == "3")
        #expect(label(1, .alphabetic) == "A")
        #expect(label(26, .alphabetic) == "Z")
        #expect(label(27, .alphabetic) == "AA")
    }

    @Test func offsetMovesEveryShape() {
        for shape in Self.allShapes {
            let moved = AnnotationObject(shape: shape).duplicated(offsetBy: CGVector(dx: 10, dy: 0))
            let b0 = AnnotationRenderer.bounds(of: AnnotationObject(shape: shape))
            let b1 = AnnotationRenderer.bounds(of: moved)
            #expect(abs(b1.minX - b0.minX - 10) < 0.001, "\(shape)")
        }
    }

    @Test func handles() {
        let box = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        #expect(HitTesting.handles(for: box).count == 8)
        let curved = AnnotationObject(shape: .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 0), style: .curved)))
        #expect(HitTesting.handles(for: curved).map(\.kind) == [.start, .end, .control])
        let line = AnnotationObject(shape: .line(start: .zero, end: CGPoint(x: 1, y: 1)))
        #expect(HitTesting.handles(for: line).count == 2)
    }

    @Test func hitTestPicksTopmost() {
        let a = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0))
        let b = AnnotationObject(shape: .rectangle(CGRect(x: 20, y: 20, width: 50, height: 50), cornerRadius: 0))
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/tmp/x.png"), pixelSize: CGSize(width: 100, height: 100), objects: [a, b])
        #expect(HitTesting.object(at: CGPoint(x: 30, y: 30), in: doc, tolerance: 0) == b.id)
        #expect(HitTesting.object(at: CGPoint(x: 5, y: 5), in: doc, tolerance: 0) == a.id)
        #expect(HitTesting.object(at: CGPoint(x: 95, y: 5), in: doc, tolerance: 0) == nil)
    }

    @Test func arrowStyleCycles() {
        #expect(ArrowStyle.straight.next == .curved)
        #expect(ArrowStyle.lineWithDot.next == .straight)
    }

    @Test func renderImageMatchesCropSize() throws {
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/tmp/none.png"), pixelSize: CGSize(width: 40, height: 20),
                                     crop: CGRect(x: 0, y: 0, width: 30, height: 10))
        let out = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: image, url: doc.baseImageURL), outputScale: 2)
        #expect(out.width == 60 && out.height == 20)
    }
}
