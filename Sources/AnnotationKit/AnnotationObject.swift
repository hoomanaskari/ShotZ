import CoreGraphics
import Foundation

public struct AnnotationObject: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var shape: Shape
    public var style: ObjectStyle

    public init(id: UUID = UUID(), shape: Shape, style: ObjectStyle = .default) {
        self.id = id
        self.shape = shape
        self.style = style
    }

    public enum Shape: Codable, Sendable, Equatable {
        case arrow(ArrowGeometry)
        case rectangle(CGRect, cornerRadius: CGFloat)
        case ellipse(CGRect)
        case line(start: CGPoint, end: CGPoint)
        case text(TextBox)
        case highlight(HighlightGeometry)
        case redact(CGRect, RedactMode)
        case counter(CounterGeometry)
        case pen([CGPoint])
    }

    /// Redactions render beneath all other objects (SPEC §5.3).
    public var isRedaction: Bool {
        if case .redact = shape { return true }
        return false
    }

    /// Same object with a fresh id (duplicate / paste).
    public func duplicated(offsetBy delta: CGVector = .zero) -> AnnotationObject {
        var copy = AnnotationObject(shape: shape, style: style)
        copy.shape = shape.offset(by: delta)
        return copy
    }
}

extension AnnotationObject.Shape {
    /// The shape translated by `delta`.
    public func offset(by d: CGVector) -> Self {
        func p(_ pt: CGPoint) -> CGPoint { CGPoint(x: pt.x + d.dx, y: pt.y + d.dy) }
        func r(_ rect: CGRect) -> CGRect { rect.offsetBy(dx: d.dx, dy: d.dy) }
        switch self {
        case .arrow(var g):
            g.start = p(g.start); g.end = p(g.end); g.control = g.control.map(p)
            return .arrow(g)
        case .rectangle(let rect, let radius):
            return .rectangle(r(rect), cornerRadius: radius)
        case .ellipse(let rect):
            return .ellipse(r(rect))
        case .line(let s, let e):
            return .line(start: p(s), end: p(e))
        case .text(var box):
            box.origin = p(box.origin)
            return .text(box)
        case .highlight(.freehand(let pts)):
            return .highlight(.freehand(pts.map(p)))
        case .highlight(.rect(let rect)):
            return .highlight(.rect(r(rect)))
        case .redact(let rect, let mode):
            return .redact(r(rect), mode)
        case .counter(var c):
            c.center = p(c.center); c.tail = c.tail.map(p)
            return .counter(c)
        case .pen(let pts):
            return .pen(pts.map(p))
        }
    }
}
