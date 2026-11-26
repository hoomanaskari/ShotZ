import CoreGraphics
import Testing
@testable import AnnotationKit

struct ArrowGeometryTests {
    @Test func headProportionsAcrossWidths() {
        var lastRatio = CGFloat.infinity
        for w in stride(from: CGFloat(2), through: 40, by: 2) {
            let m = ArrowPath.headMetrics(width: w, style: .straight, arrowLength: 10_000)
            let ratio = m.length / w
            // Thin lines get proportionally bigger heads, thick lines smaller, within sane bounds.
            #expect(ratio > 3.8 && ratio < 9, "w \(w): ratio \(ratio)")
            #expect(ratio <= lastRatio)
            #expect(abs(m.halfWidth / m.length - 0.5) < 0.001)
            lastRatio = ratio
        }
    }

    @Test(arguments: ArrowStyle.allCases) func shortThickArrowsKeepARealHead(_ style: ArrowStyle) {
        let g = ArrowGeometry(start: .zero, end: CGPoint(x: 70, y: 0), control: CGPoint(x: 35, y: -25), style: style)
        let arrow = ArrowPath.make(g, width: 29)
        let head = arrow.fills.last { $0.boundingBoxOfPath.maxX > 60 } ?? arrow.fills[arrow.fills.count - 1]
        // The head stays ≥ ~3× the (narrowed) shaft: never a stub or a pill.
        #expect(head.boundingBoxOfPath.height >= arrow.shaftWidth * 2.9, "\(style): head \(head.boundingBoxOfPath) shaft \(arrow.shaftWidth)")
        #expect(arrow.shaftWidth < 29)
        // Long arrows keep the requested width.
        #expect(ArrowPath.make(ArrowGeometry(start: .zero, end: CGPoint(x: 900, y: 0), style: style), width: 29).shaftWidth == 29)
    }

    @Test func curvedShaftArrivesAlongTheHeadAxis() {
        // A strong bend: the last shaft segment must point the same way as the head.
        let g = ArrowGeometry(start: CGPoint(x: 0, y: 200), end: CGPoint(x: 200, y: 160), control: CGPoint(x: 60, y: -40), style: .curved)
        let arrow = ArrowPath.make(g, width: 10)
        var lastControl = CGPoint.zero, lastPoint = CGPoint.zero
        arrow.shaft?.applyWithBlock { e in
            let el = e.pointee
            if el.type == .addCurveToPoint { lastControl = el.points[1]; lastPoint = el.points[2] }
        }
        let shaftDir = atan2(lastPoint.y - lastControl.y, lastPoint.x - lastControl.x)
        let head = arrow.fills[0].boundingBoxOfPath
        #expect(head.contains(lastPoint), "shaft must end inside the head")
        // Head axis: from the shaft end to the tip (the endpoint).
        let axis = atan2(g.end.y - lastPoint.y, g.end.x - lastPoint.x)
        #expect(abs(shaftDir - axis) < 0.02, "kink: \(shaftDir) vs \(axis)")
    }
}
