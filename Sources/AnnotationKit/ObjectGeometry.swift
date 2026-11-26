import CoreGraphics

/// Modifier keys that change how a handle drag behaves (SPEC §5.2).
public struct TransformModifiers: OptionSet, Sendable, Hashable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    /// ⇧: keep aspect ratio for boxes, snap lines/arrows/tails to 15°.
    public static let constrain = TransformModifiers(rawValue: 1 << 0)
    /// ⌥: resize symmetrically about the centre.
    public static let fromCenter = TransformModifiers(rawValue: 1 << 1)
}

/// Pure move / resize maths for the editor. Every function takes the object as it was when
/// the drag began plus the current pointer, so repeated calls during a drag never drift.
public enum ObjectGeometry {
    /// The object's geometric frame without stroke (selection outline, handles, snapping, marquee).
    public static func frame(of object: AnnotationObject) -> CGRect {
        switch object.shape {
        case .arrow(let g):
            let path = CGMutablePath()
            path.move(to: g.start)
            path.addQuadCurve(to: g.end, control: g.bezierControl)
            return path.boundingBoxOfPath
        case .line(let s, let e):
            return Geometry.rect(s, e)
        case .rectangle(let r, _), .ellipse(let r), .redact(let r, _), .highlight(.rect(let r)):
            return r.standardized
        case .text(let box):
            return TextLayout(box: box, fontSize: object.style.fontSize).frame
        case .highlight(.freehand(let pts)), .pen(let pts):
            return Geometry.rectContaining(pts)
        case .counter(let c):
            let r = object.style.fontSize
            return CGRect(x: c.center.x - r, y: c.center.y - r, width: 2 * r, height: 2 * r)
        }
    }

    /// The object translated by `delta` (pass through `AngleSnapping.axisConstrained` for ⇧).
    public static func moved(_ object: AnnotationObject, by delta: CGVector) -> AnnotationObject {
        var o = object
        o.shape = object.shape.offset(by: delta)
        return o
    }

    /// The object with `handle` dragged to `point`.
    public static func resized(_ original: AnnotationObject, handle: Handle.Kind, to point: CGPoint,
                               modifiers: TransformModifiers = []) -> AnnotationObject {
        var o = original
        switch original.shape {
        case .arrow(var g):
            switch handle {
            case .start:
                let p = modifiers.contains(.constrain) ? AngleSnapping.snap(point, around: g.end) : point
                g.control = g.control.map { shiftControl($0, by: CGVector(dx: p.x - g.start.x, dy: p.y - g.start.y)) }
                g.start = p
            case .end:
                let p = modifiers.contains(.constrain) ? AngleSnapping.snap(point, around: g.start) : point
                g.control = g.control.map { shiftControl($0, by: CGVector(dx: p.x - g.end.x, dy: p.y - g.end.y)) }
                g.end = p
            case .control:
                g.control = point
            default:
                return original
            }
            o.shape = .arrow(g)
        case .line(let s, let e):
            switch handle {
            case .start: o.shape = .line(start: modifiers.contains(.constrain) ? AngleSnapping.snap(point, around: e) : point, end: e)
            case .end: o.shape = .line(start: s, end: modifiers.contains(.constrain) ? AngleSnapping.snap(point, around: s) : point)
            default: return original
            }
        case .counter(var c):
            guard handle == .tail else { return original }
            c.tail = modifiers.contains(.constrain) ? AngleSnapping.snap(point, around: c.center) : point
            o.shape = .counter(c)
        case .rectangle(let r, let radius):
            o.shape = .rectangle(resizedRect(r.standardized, handle: handle, to: point, modifiers: modifiers), cornerRadius: radius)
        case .ellipse(let r):
            o.shape = .ellipse(resizedRect(r.standardized, handle: handle, to: point, modifiers: modifiers))
        case .redact(let r, let mode):
            o.shape = .redact(resizedRect(r.standardized, handle: handle, to: point, modifiers: modifiers), mode)
        case .highlight(.rect(let r)):
            o.shape = .highlight(.rect(resizedRect(r.standardized, handle: handle, to: point, modifiers: modifiers)))
        case .highlight(.freehand(let pts)):
            let old = Geometry.rectContaining(pts)
            o.shape = .highlight(.freehand(map(pts, from: old, to: resizedRect(old, handle: handle, to: point, modifiers: modifiers))))
        case .pen(let pts):
            let old = Geometry.rectContaining(pts)
            o.shape = .pen(map(pts, from: old, to: resizedRect(old, handle: handle, to: point, modifiers: modifiers)))
        case .text(var box):
            let old = TextLayout(box: box, fontSize: original.style.fontSize).frame
            switch handle {
            case .left, .right:
                // Side handles set the wrap width (SPEC §5.3).
                let minWidth = original.style.fontSize * 2
                if handle == .right {
                    box.wrapWidth = max(point.x - old.minX, minWidth)
                } else {
                    let width = max(old.maxX - point.x, minWidth)
                    box.wrapWidth = width
                    box.origin.x = old.maxX - width
                }
            case .topLeft, .topRight, .bottomLeft, .bottomRight:
                // Corner handles scale the font, always keeping proportions.
                let r = resizedRect(old, handle: handle, to: point, modifiers: modifiers.union(.constrain))
                let k = max(r.width / max(old.width, 1), 0.05)
                o.style.fontSize = max((original.style.fontSize * k * 2).rounded() / 2, 4)
                box.wrapWidth = box.wrapWidth.map { $0 * k }
                box.origin = r.origin
            default:
                return original
            }
            o.shape = .text(box)
        }
        return o
    }

    /// A box with one of its 8 handles dragged to `point`. ⇧ keeps the aspect ratio; ⌥ resizes
    /// about the centre. Dragging past the opposite edge flips the box (the result is standardized).
    public static func resizedRect(_ r: CGRect, handle: Handle.Kind, to point: CGPoint, modifiers: TransformModifiers = []) -> CGRect {
        let movesLeft = [.topLeft, .left, .bottomLeft].contains(handle)
        let movesRight = [.topRight, .right, .bottomRight].contains(handle)
        let movesTop = [.topLeft, .top, .topRight].contains(handle)
        let movesBottom = [.bottomLeft, .bottom, .bottomRight].contains(handle)
        guard movesLeft || movesRight || movesTop || movesBottom else { return r }
        let center = modifiers.contains(.fromCenter)
        let anchorX = center ? r.midX : (movesLeft ? r.maxX : r.minX)
        let anchorY = center ? r.midY : (movesTop ? r.maxY : r.minY)
        // Signed extents from the anchor; unmoved axes keep their original extent.
        var ex = movesLeft || movesRight ? point.x - anchorX : (center ? r.width / 2 : r.width)
        var ey = movesTop || movesBottom ? point.y - anchorY : (center ? r.height / 2 : r.height)
        if modifiers.contains(.constrain), r.width > 0, r.height > 0 {
            let baseW = center ? r.width / 2 : r.width, baseH = center ? r.height / 2 : r.height
            let sx = abs(ex) / baseW, sy = abs(ey) / baseH
            let corner = (movesLeft || movesRight) && (movesTop || movesBottom)
            let s = corner ? max(sx, sy) : ((movesLeft || movesRight) ? sx : sy)
            let signX: CGFloat = (movesLeft || movesRight) ? (ex < 0 ? -1 : 1) : 1
            let signY: CGFloat = (movesTop || movesBottom) ? (ey < 0 ? -1 : 1) : 1
            ex = signX * baseW * s
            ey = signY * baseH * s
            if !corner {
                // Side handle with ⇧: grow the other axis symmetrically about its centre.
                if movesLeft || movesRight {
                    let h = baseH * s * (center ? 2 : 1)
                    let x = center ? CGRect(x: anchorX - ex, y: 0, width: 2 * ex, height: 0) : CGRect(x: anchorX, y: 0, width: ex, height: 0)
                    return CGRect(x: x.standardized.minX, y: r.midY - h / 2, width: abs(x.width), height: h).standardized
                } else {
                    let w = baseW * s * (center ? 2 : 1)
                    let y = center ? CGRect(x: 0, y: anchorY - ey, width: 0, height: 2 * ey) : CGRect(x: 0, y: anchorY, width: 0, height: ey)
                    return CGRect(x: r.midX - w / 2, y: y.standardized.minY, width: w, height: abs(y.height)).standardized
                }
            }
        }
        let xRange: (CGFloat, CGFloat)
        if movesLeft || movesRight {
            xRange = center ? (anchorX - ex, anchorX + ex) : (anchorX, anchorX + ex)
        } else {
            xRange = (r.minX, r.maxX)
        }
        let yRange: (CGFloat, CGFloat)
        if movesTop || movesBottom {
            yRange = center ? (anchorY - ey, anchorY + ey) : (anchorY, anchorY + ey)
        } else {
            yRange = (r.minY, r.maxY)
        }
        return CGRect(x: xRange.0, y: yRange.0, width: xRange.1 - xRange.0, height: yRange.1 - yRange.0).standardized
    }

    private static func shiftControl(_ c: CGPoint, by d: CGVector) -> CGPoint {
        CGPoint(x: c.x + d.dx / 2, y: c.y + d.dy / 2)
    }

    /// Maps points proportionally from one frame to another (degenerate axes just translate).
    static func map(_ pts: [CGPoint], from old: CGRect, to new: CGRect) -> [CGPoint] {
        let sx = old.width > 0.001 ? new.width / old.width : 1
        let sy = old.height > 0.001 ? new.height / old.height : 1
        return pts.map { CGPoint(x: new.minX + ($0.x - old.minX) * sx, y: new.minY + ($0.y - old.minY) * sy) }
    }
}
