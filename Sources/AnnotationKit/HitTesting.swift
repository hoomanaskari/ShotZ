import CoreGraphics

/// Pure geometry, unit-tested.
public enum HitTesting {
    /// Topmost object at `point`, in paint order (redactions are beneath everything else).
    /// Strokes (lines, arrows, outlines, pen) are hit within half their width plus `tolerance`;
    /// filled shapes, text boxes, counters, highlights and redactions by their area.
    public static func object(
        at point: CGPoint, in document: AnnotationDocument, tolerance: CGFloat
    ) -> AnnotationObject.ID? {
        AnnotationRenderer.paintOrder(document.objects).last { contains(point, object: $0, tolerance: tolerance) }?.id
    }

    /// Every object id at `point`, topmost first (for click-through / cycling selection).
    public static func objects(at point: CGPoint, in document: AnnotationDocument, tolerance: CGFloat) -> [AnnotationObject.ID] {
        AnnotationRenderer.paintOrder(document.objects).reversed().filter { contains(point, object: $0, tolerance: tolerance) }.map(\.id)
    }

    /// Ids of objects whose geometric frame intersects `rect` (marquee selection), in z-order.
    public static func objects(intersecting rect: CGRect, in document: AnnotationDocument) -> [AnnotationObject.ID] {
        let r = rect.standardized
        return document.objects.filter { ObjectGeometry.frame(of: $0).intersects(r) }.map(\.id)
    }

    public static func contains(_ point: CGPoint, object: AnnotationObject, tolerance: CGFloat) -> Bool {
        let tol = max(tolerance, 0)
        let style = object.style
        // Cheap reject first.
        guard AnnotationRenderer.bounds(of: object).insetBy(dx: -tol, dy: -tol).contains(point) else { return false }
        func strokeHit(_ path: CGPath, width: CGFloat) -> Bool {
            path.copy(strokingWithWidth: width + 2 * tol, lineCap: .round, lineJoin: .round, miterLimit: 10).contains(point)
        }
        switch object.shape {
        case .arrow(let g):
            let arrow = ArrowPath.make(g, width: style.lineWidth)
            if let shaft = arrow.shaft, !shaft.isEmpty, strokeHit(shaft, width: arrow.shaftWidth) { return true }
            return arrow.fills.contains { $0.contains(point) || strokeHit($0, width: arrow.fillRounding) }
        case .rectangle(let rect, let radius):
            let path = AnnotationRenderer.boxPath(rect, cornerRadius: radius, ellipse: false)
            return style.fill != .outline && path.contains(point) || strokeHit(path, width: style.lineWidth)
        case .ellipse(let rect):
            let path = AnnotationRenderer.boxPath(rect, cornerRadius: 0, ellipse: true)
            return style.fill != .outline && path.contains(point) || strokeHit(path, width: style.lineWidth)
        case .line(let s, let e):
            return Geometry.distanceToSegment(point, s, e) <= style.lineWidth / 2 + tol
        case .text(let box):
            return TextLayout(box: box, fontSize: style.fontSize).frame.insetBy(dx: -tol, dy: -tol).contains(point)
        case .highlight(.freehand(let pts)), .pen(let pts):
            guard !pts.isEmpty else { return false }
            return strokeHit(StrokeSmoothing.path(through: pts), width: style.lineWidth)
        case .highlight(.rect(let rect)), .redact(let rect, _):
            return rect.standardized.insetBy(dx: -tol, dy: -tol).contains(point)
        case .counter(let c):
            let shape = CounterShape(c, radius: style.fontSize)
            return shape.path.contains(point) || strokeHit(shape.path, width: 0)
        }
    }

    /// Handles for an object (SPEC §5.2):
    /// - boxes (rectangle, ellipse, rect highlight, redaction, pen, freehand highlight): 8;
    /// - arrows: start, end, and the mid-point curve handle for curved arrows;
    /// - lines: start, end;
    /// - text: 4 corners (scale the font) and left/right (set the wrap width);
    /// - counters: the tail tip if there is one.
    public static func handles(for object: AnnotationObject) -> [Handle] {
        switch object.shape {
        case .arrow(let g):
            var hs = [Handle(kind: .start, position: g.start), Handle(kind: .end, position: g.end)]
            if g.style == .curved { hs.append(Handle(kind: .control, position: g.handlePoint)) }
            return hs
        case .line(let s, let e):
            return [Handle(kind: .start, position: s), Handle(kind: .end, position: e)]
        case .rectangle, .ellipse, .redact, .highlight, .pen:
            return boxHandles(ObjectGeometry.frame(of: object))
        case .text:
            let kinds: Set<Handle.Kind> = [.topLeft, .topRight, .bottomLeft, .bottomRight, .left, .right]
            return boxHandles(ObjectGeometry.frame(of: object)).filter { kinds.contains($0.kind) }
        case .counter(let c):
            return c.tail.map { [Handle(kind: .tail, position: $0)] } ?? []
        }
    }

    /// The handle under `point` (within `tolerance`), nearest first.
    public static func handle(at point: CGPoint, for object: AnnotationObject, tolerance: CGFloat) -> Handle? {
        handles(for: object)
            .filter { Geometry.distance($0.position, point) <= tolerance }
            .min { Geometry.distance($0.position, point) < Geometry.distance($1.position, point) }
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
