import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

struct TransformTests {
    let r = CGRect(x: 100, y: 100, width: 200, height: 100)

    @Test func cornerAndSideResize() {
        #expect(ObjectGeometry.resizedRect(r, handle: .bottomRight, to: CGPoint(x: 350, y: 260)) == CGRect(x: 100, y: 100, width: 250, height: 160))
        #expect(ObjectGeometry.resizedRect(r, handle: .left, to: CGPoint(x: 50, y: 999)) == CGRect(x: 50, y: 100, width: 250, height: 100))
        #expect(ObjectGeometry.resizedRect(r, handle: .top, to: CGPoint(x: 0, y: 80)) == CGRect(x: 100, y: 80, width: 200, height: 120))
        // Dragging past the opposite edge flips.
        #expect(ObjectGeometry.resizedRect(r, handle: .right, to: CGPoint(x: 60, y: 0)) == CGRect(x: 60, y: 100, width: 40, height: 100))
    }

    @Test func shiftKeepsAspectOptionResizesFromCentre() {
        let s = ObjectGeometry.resizedRect(r, handle: .bottomRight, to: CGPoint(x: 500, y: 210), modifiers: .constrain)
        #expect(s == CGRect(x: 100, y: 100, width: 400, height: 200))
        let c = ObjectGeometry.resizedRect(r, handle: .bottomRight, to: CGPoint(x: 320, y: 220), modifiers: .fromCenter)
        #expect(c == CGRect(x: 80, y: 80, width: 240, height: 140))
        let both = ObjectGeometry.resizedRect(r, handle: .topLeft, to: CGPoint(x: 0, y: 140), modifiers: [.constrain, .fromCenter])
        #expect(both == CGRect(x: 0, y: 50, width: 400, height: 200))
        let side = ObjectGeometry.resizedRect(r, handle: .right, to: CGPoint(x: 500, y: 0), modifiers: .constrain)
        #expect(side == CGRect(x: 100, y: 50, width: 400, height: 200))
    }

    @Test func lineEndpointsSnapTo15Degrees() {
        let line = AnnotationObject(shape: .line(start: .zero, end: CGPoint(x: 100, y: 0)))
        let moved = ObjectGeometry.resized(line, handle: .end, to: CGPoint(x: 100, y: 12), modifiers: .constrain)
        guard case .line(_, let e) = moved.shape else { Issue.record("not a line"); return }
        #expect(abs(e.y) < 1e-9 && abs(e.x - hypot(100, 12)) < 1e-9)
        let p = AngleSnapping.snap(CGPoint(x: 100, y: 95), around: .zero)
        #expect(abs(atan2(p.y, p.x) * 180 / .pi - 45) < 1e-9)
        let q = AngleSnapping.snap(CGPoint(x: 10, y: 100), around: .zero)
        #expect(q.x == 0)
        #expect(AngleSnapping.axisConstrained(CGVector(dx: 3, dy: -8)) == CGVector(dx: 0, dy: -8))
    }

    @Test func arrowEndpointsCarryTheCurveHandle() {
        let g = ArrowGeometry(start: .zero, end: CGPoint(x: 100, y: 0), control: CGPoint(x: 50, y: 40), style: .curved)
        let a = AnnotationObject(shape: .arrow(g))
        let moved = ObjectGeometry.resized(a, handle: .end, to: CGPoint(x: 200, y: 0))
        guard case .arrow(let m) = moved.shape else { Issue.record("not an arrow"); return }
        #expect(m.end == CGPoint(x: 200, y: 0) && m.control == CGPoint(x: 100, y: 40))
        let bent = ObjectGeometry.resized(a, handle: .control, to: CGPoint(x: 50, y: -20))
        guard case .arrow(let b) = bent.shape else { Issue.record("not an arrow"); return }
        #expect(b.control == CGPoint(x: 50, y: -20))
        #expect(Geometry.distance(b.point(at: 0.5), CGPoint(x: 50, y: -20)) < 1e-9)
    }

    @Test func textSidesWrapAndCornersScale() {
        let box = TextBox(origin: CGPoint(x: 10, y: 10), string: "Some longer text that will wrap")
        let text = AnnotationObject(shape: .text(box), style: ObjectStyle(fontSize: 20))
        let frame = ObjectGeometry.frame(of: text)
        let wrapped = ObjectGeometry.resized(text, handle: .right, to: CGPoint(x: 130, y: 0))
        guard case .text(let w) = wrapped.shape else { Issue.record("not text"); return }
        #expect(w.wrapWidth == 120)
        #expect(ObjectGeometry.frame(of: wrapped).height > frame.height) // now on several lines
        let fromLeft = ObjectGeometry.resized(text, handle: .left, to: CGPoint(x: frame.maxX - 100, y: 0))
        guard case .text(let l) = fromLeft.shape else { Issue.record("not text"); return }
        #expect(l.wrapWidth == 100 && l.origin.x == frame.maxX - 100)
        let scaled = ObjectGeometry.resized(text, handle: .bottomRight, to: CGPoint(x: frame.minX + frame.width * 2, y: frame.maxY))
        #expect(scaled.style.fontSize == 40)
        guard case .text(let s) = scaled.shape else { Issue.record("not text"); return }
        #expect(s.origin == box.origin)
    }

    @Test func penScalesPoints() {
        let pen = AnnotationObject(shape: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), CGPoint(x: 100, y: 0)]))
        let big = ObjectGeometry.resized(pen, handle: .bottomRight, to: CGPoint(x: 200, y: 40))
        #expect(big.shape == .pen([CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 40), CGPoint(x: 200, y: 0)]))
        let counter = AnnotationObject(shape: .counter(CounterGeometry(center: .zero, tail: CGPoint(x: 10, y: 0), value: 1)))
        let tail = ObjectGeometry.resized(counter, handle: .tail, to: CGPoint(x: 0, y: 30))
        guard case .counter(let c) = tail.shape else { Issue.record("not a counter"); return }
        #expect(c.tail == CGPoint(x: 0, y: 30))
    }

    @Test func snappingToImageAndObjects() {
        let other = AnnotationObject(shape: .rectangle(CGRect(x: 300, y: 50, width: 100, height: 40), cornerRadius: 0))
        let moving = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 50, height: 50), cornerRadius: 0))
        let doc = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 1000, height: 600), objects: [other, moving])
        let targets = Snapping.targets(in: doc, excluding: [moving.id])
        // Centre near the image centre (500, 300) snaps on both axes.
        let a = Snapping.snap(frame: CGRect(x: 472, y: 277, width: 50, height: 50), to: targets, threshold: 5)
        #expect(a.offset == CGVector(dx: 3, dy: -2))
        #expect(a.guides.contains { $0.axis == .vertical && $0.position == 500 && $0.start == 0 && $0.end == 600 })
        #expect(a.guides.contains { $0.axis == .horizontal && $0.position == 300 })
        // Left edge near the other object's right edge (400); top near its top (50).
        let b = Snapping.snap(frame: CGRect(x: 402, y: 47, width: 50, height: 20), to: targets, threshold: 5)
        #expect(b.offset == CGVector(dx: -2, dy: 3))
        // Beyond the threshold: nothing.
        let c = Snapping.snap(frame: CGRect(x: 420, y: 120, width: 50, height: 50), to: targets, threshold: 5)
        #expect(c.offset == .zero && c.guides.isEmpty)
        let p = Snapping.snap(point: CGPoint(x: 997, y: 3), to: targets, threshold: 5)
        #expect(p.point == CGPoint(x: 1000, y: 0))
    }

    @Test func smoothingKeepsEndpointsAndReducesJitter() {
        var raw: [CGPoint] = []
        for i in 0...200 { raw.append(CGPoint(x: CGFloat(i), y: i % 2 == 0 ? 0 : 1.5)) }
        let smooth = StrokeSmoothing.smooth(raw)
        #expect(smooth.first == raw.first && smooth.last == raw.last)
        #expect(smooth.count < raw.count / 4)
        #expect(smooth.allSatisfy { $0.y > -0.01 && $0.y < 1.51 })
        #expect(StrokeSmoothing.straightened(raw) == [raw[0], raw[200]])
        #expect(StrokeSmoothing.simplify([.zero, CGPoint(x: 1, y: 0.01), CGPoint(x: 2, y: 0)], epsilon: 0.1).count == 2)
    }
}
