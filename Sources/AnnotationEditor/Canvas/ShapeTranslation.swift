import AnnotationKit
import CoreGraphics

/// Detects when an object only moved, so the canvas can move its layer
/// instead of re-rasterising it. Pure; unit-tested.
enum ShapeTranslation {
    static let epsilon: CGFloat = 0.01

    /// The translation that turns `old` into `new`, or nil if anything else changed.
    static func delta(from old: AnnotationObject, to new: AnnotationObject) -> CGVector? {
        guard old.style == new.style else { return nil }
        return delta(from: old.shape, to: new.shape)
    }

    static func delta(from a: AnnotationObject.Shape, to b: AnnotationObject.Shape) -> CGVector? {
        switch (a, b) {
        case (.arrow(let g1), .arrow(let g2)):
            guard g1.style == g2.style, (g1.control == nil) == (g2.control == nil) else { return nil }
            let d = diff(g1.start, g2.start)
            guard same(g1.end, g2.end, d) else { return nil }
            if let c1 = g1.control, let c2 = g2.control, !same(c1, c2, d) { return nil }
            return d
        case (.rectangle(let r1, let c1), .rectangle(let r2, let c2)):
            guard c1 == c2 else { return nil }
            return rectDelta(r1, r2)
        case (.ellipse(let r1), .ellipse(let r2)):
            return rectDelta(r1, r2)
        // Redactions sample the pixels under them, so a moved redaction always
        // re-renders (falls through to `default`).
        case (.highlight(.rect(let r1)), .highlight(.rect(let r2))):
            return rectDelta(r1, r2)
        case (.line(let s1, let e1), .line(let s2, let e2)):
            let d = diff(s1, s2)
            return same(e1, e2, d) ? d : nil
        case (.text(let t1), .text(let t2)):
            guard t1.string == t2.string, t1.wrapWidth == t2.wrapWidth, t1.style == t2.style else { return nil }
            return diff(t1.origin, t2.origin)
        case (.highlight(.freehand(let p1)), .highlight(.freehand(let p2))), (.pen(let p1), .pen(let p2)):
            return pointsDelta(p1, p2)
        case (.counter(let c1), .counter(let c2)):
            guard c1.value == c2.value, c1.numbering == c2.numbering, (c1.tail == nil) == (c2.tail == nil) else { return nil }
            let d = diff(c1.center, c2.center)
            if let t1 = c1.tail, let t2 = c2.tail, !same(t1, t2, d) { return nil }
            return d
        default:
            return nil
        }
    }

    private static func diff(_ a: CGPoint, _ b: CGPoint) -> CGVector {
        CGVector(dx: b.x - a.x, dy: b.y - a.y)
    }

    private static func same(_ a: CGPoint, _ b: CGPoint, _ d: CGVector) -> Bool {
        abs(a.x + d.dx - b.x) < epsilon && abs(a.y + d.dy - b.y) < epsilon
    }

    private static func rectDelta(_ a: CGRect, _ b: CGRect) -> CGVector? {
        guard abs(a.width - b.width) < epsilon, abs(a.height - b.height) < epsilon else { return nil }
        return diff(a.origin, b.origin)
    }

    private static func pointsDelta(_ a: [CGPoint], _ b: [CGPoint]) -> CGVector? {
        guard a.count == b.count, let a0 = a.first, let b0 = b.first else { return a.isEmpty && b.isEmpty ? .zero : nil }
        let d = diff(a0, b0)
        for i in a.indices where !same(a[i], b[i], d) { return nil }
        return d
    }
}
