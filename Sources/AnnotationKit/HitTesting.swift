import CoreGraphics

/// Pure geometry, unit-tested.
public enum HitTesting {
    /// Topmost object at `point`. TODO(engineer C): precise per-shape hit tests
    /// (stroke distance, ellipse interior, text glyph box). Bounds-based for now.
    public static func object(
        at point: CGPoint, in document: AnnotationDocument, tolerance: CGFloat
    ) -> AnnotationObject.ID? {
        document.objects.last { object in
            AnnotationRenderer.bounds(of: object).insetBy(dx: -tolerance, dy: -tolerance).contains(point)
        }?.id
    }

    /// 8 handles for box shapes, start/end (+ control) for lines and arrows.
    public static func handles(for object: AnnotationObject) -> [Handle] {
        switch object.shape {
        case .arrow(let g):
            var hs = [Handle(kind: .start, position: g.start), Handle(kind: .end, position: g.end)]
            if g.style == .curved {
                let mid = g.control ?? CGPoint(x: (g.start.x + g.end.x) / 2, y: (g.start.y + g.end.y) / 2)
                hs.append(Handle(kind: .control, position: mid))
            }
            return hs
        case .line(let s, let e):
            return [Handle(kind: .start, position: s), Handle(kind: .end, position: e)]
        case .rectangle(let r, _), .ellipse(let r), .redact(let r, _), .highlight(.rect(let r)):
            return boxHandles(r.standardized)
        case .counter(let c):
            return c.tail.map { [Handle(kind: .tail, position: $0)] } ?? []
        case .text, .highlight(.freehand), .pen:
            return boxHandles(AnnotationRenderer.bounds(of: object))
        }
    }

    static func boxHandles(_ r: CGRect) -> [Handle] {
        [
            Handle(kind: .topLeft, position: CGPoint(x: r.minX, y: r.minY)),
            Handle(kind: .top, position: CGPoint(x: r.midX, y: r.minY)),
            Handle(kind: .topRight, position: CGPoint(x: r.maxX, y: r.minY)),
            Handle(kind: .right, position: CGPoint(x: r.maxX, y: r.midY)),
            Handle(kind: .bottomRight, position: CGPoint(x: r.maxX, y: r.maxY)),
            Handle(kind: .bottom, position: CGPoint(x: r.midX, y: r.maxY)),
            Handle(kind: .bottomLeft, position: CGPoint(x: r.minX, y: r.maxY)),
            Handle(kind: .left, position: CGPoint(x: r.minX, y: r.midY)),
        ]
    }
}
