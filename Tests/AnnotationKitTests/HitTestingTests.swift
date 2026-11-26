import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

struct HitTestingTests {
    let size = CGSize(width: 400, height: 300)
    func doc(_ objects: [AnnotationObject]) -> AnnotationDocument {
        AnnotationDocument(baseImageURL: URL(filePath: "/tmp/x.png"), pixelSize: size, objects: objects)
    }
    func style(width: CGFloat = 4, fill: ObjectStyle.FillMode = .outline) -> ObjectStyle {
        ObjectStyle(lineWidth: width, fill: fill, fontSize: 20)
    }

    @Test func lineHitWithinHalfWidthPlusTolerance() {
        let line = AnnotationObject(shape: .line(start: CGPoint(x: 10, y: 10), end: CGPoint(x: 210, y: 10)), style: style(width: 4))
        let d = doc([line])
        #expect(HitTesting.object(at: CGPoint(x: 100, y: 13.9), in: d, tolerance: 2) == line.id)
        #expect(HitTesting.object(at: CGPoint(x: 100, y: 16.5), in: d, tolerance: 2) == nil)
        #expect(HitTesting.object(at: CGPoint(x: 100, y: 16.5), in: d, tolerance: 5) == line.id)
    }

    @Test func curvedArrowHitFollowsTheCurve() {
        let g = ArrowGeometry(start: CGPoint(x: 0, y: 200), end: CGPoint(x: 200, y: 200), control: CGPoint(x: 100, y: 100), style: .curved)
        let arrow = AnnotationObject(shape: .arrow(g), style: style())
        let d = doc([arrow])
        // The curve passes through its handle point at t = 0.5.
        #expect(HitTesting.object(at: CGPoint(x: 100, y: 100), in: d, tolerance: 1) == arrow.id)
        // The chord midpoint is far from the curve.
        #expect(HitTesting.object(at: CGPoint(x: 100, y: 200), in: d, tolerance: 1) == nil)
        // The head near the tip is hittable.
        #expect(HitTesting.object(at: CGPoint(x: 198, y: 199), in: d, tolerance: 0) == arrow.id)
    }

    @Test func outlineBoxesHitOnStrokeFilledBoxesInside() {
        let outline = AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 10, width: 100, height: 100), cornerRadius: 0), style: style())
        let filled = AnnotationObject(shape: .ellipse(CGRect(x: 200, y: 10, width: 100, height: 100)), style: style(fill: .filled))
        let translucent = AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 150, width: 100, height: 100), cornerRadius: 10),
                                           style: style(fill: .outlineTranslucentFill))
        let d = doc([outline, filled, translucent])
        #expect(HitTesting.object(at: CGPoint(x: 60, y: 60), in: d, tolerance: 2) == nil)
        #expect(HitTesting.object(at: CGPoint(x: 11, y: 60), in: d, tolerance: 2) == outline.id)
        #expect(HitTesting.object(at: CGPoint(x: 250, y: 60), in: d, tolerance: 0) == filled.id)
        // Ellipse corner region is outside the ellipse.
        #expect(HitTesting.object(at: CGPoint(x: 203, y: 13), in: d, tolerance: 0) == nil)
        #expect(HitTesting.object(at: CGPoint(x: 60, y: 200), in: d, tolerance: 0) == translucent.id)
    }

    @Test func redactionsAreBeneathRegardlessOfOrder() {
        let box = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 100, height: 100), cornerRadius: 0), style: style(fill: .filled))
        let redact = AnnotationObject(shape: .redact(CGRect(x: 0, y: 0, width: 100, height: 100), .blur))
        let d = doc([box, redact])
        #expect(HitTesting.object(at: CGPoint(x: 50, y: 50), in: d, tolerance: 0) == box.id)
        #expect(HitTesting.objects(at: CGPoint(x: 50, y: 50), in: d, tolerance: 0) == [box.id, redact.id])
    }

    @Test func textCounterPenAndHighlightHits() {
        let text = AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 10, y: 10), string: "Hello")), style: style())
        let counter = AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: 300, y: 50), tail: CGPoint(x: 360, y: 120), value: 1)),
                                       style: style())
        let pen = AnnotationObject(shape: .pen([CGPoint(x: 20, y: 200), CGPoint(x: 120, y: 220), CGPoint(x: 200, y: 200)]), style: style(width: 6))
        let marker = AnnotationObject(shape: .highlight(.rect(CGRect(x: 250, y: 200, width: 100, height: 30))), style: style())
        let d = doc([text, counter, pen, marker])
        let frame = TextLayout(box: TextBox(origin: CGPoint(x: 10, y: 10), string: "Hello"), fontSize: 20).frame
        #expect(HitTesting.object(at: CGPoint(x: frame.midX, y: frame.midY), in: d, tolerance: 0) == text.id)
        #expect(HitTesting.object(at: CGPoint(x: 300, y: 50), in: d, tolerance: 0) == counter.id)
        #expect(HitTesting.object(at: CGPoint(x: 352, y: 108), in: d, tolerance: 1) == counter.id) // along the tail
        #expect(HitTesting.object(at: CGPoint(x: 120, y: 220), in: d, tolerance: 0) == pen.id)
        #expect(HitTesting.object(at: CGPoint(x: 120, y: 250), in: d, tolerance: 2) == nil)
        #expect(HitTesting.object(at: CGPoint(x: 300, y: 215), in: d, tolerance: 0) == marker.id)
    }

    @Test func marqueeSelectsIntersectingFrames() {
        let a = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        let b = AnnotationObject(shape: .line(start: CGPoint(x: 50, y: 50), end: CGPoint(x: 90, y: 90)))
        #expect(HitTesting.objects(intersecting: CGRect(x: 40, y: 40, width: 20, height: 20), in: doc([a, b])) == [b.id])
        #expect(HitTesting.objects(intersecting: CGRect(x: 95, y: 95, width: -100, height: -100), in: doc([a, b])) == [a.id, b.id])
    }

    @Test func handlesPerShape() {
        func kinds(_ shape: AnnotationObject.Shape) -> [Handle.Kind] {
            HitTesting.handles(for: AnnotationObject(shape: shape, style: style())).map(\.kind)
        }
        #expect(kinds(.ellipse(CGRect(x: 0, y: 0, width: 10, height: 10))).count == 8)
        #expect(kinds(.redact(CGRect(x: 0, y: 0, width: 10, height: 10), .pixelate)).count == 8)
        #expect(kinds(.pen([.zero, CGPoint(x: 5, y: 9)])).count == 8)
        #expect(kinds(.arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 9, y: 9)))) == [.start, .end])
        #expect(Set(kinds(.text(TextBox(origin: .zero, string: "a")))) == [.topLeft, .topRight, .bottomLeft, .bottomRight, .left, .right])
        #expect(kinds(.counter(CounterGeometry(center: .zero, value: 1))).isEmpty)
        #expect(kinds(.counter(CounterGeometry(center: .zero, tail: CGPoint(x: 40, y: 0), value: 1))) == [.tail])
        let rect = HitTesting.handles(for: AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 20, width: 30, height: 40), cornerRadius: 0)))
        #expect(rect.first { $0.kind == .bottomRight }?.position == CGPoint(x: 40, y: 60))
        #expect(rect.first { $0.kind == .top }?.position == CGPoint(x: 25, y: 20))
        let curved = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 30), style: .curved)
        #expect(HitTesting.handles(for: AnnotationObject(shape: .arrow(curved))).last?.position == CGPoint(x: 50, y: 30))
        let o = AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 20, width: 30, height: 40), cornerRadius: 0))
        #expect(HitTesting.handle(at: CGPoint(x: 41, y: 59), for: o, tolerance: 3)?.kind == .bottomRight)
        #expect(HitTesting.handle(at: CGPoint(x: 25, y: 40), for: o, tolerance: 3) == nil)
    }
}
