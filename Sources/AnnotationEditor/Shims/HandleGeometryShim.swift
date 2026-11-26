import AnnotationKit
import CoreGraphics

// TEMP until AnnotationKit provides handle geometry (resize/rotate maths per handle).
// Pure; unit-tested in HandleGeometryShimTests.
enum HandleGeometryShim {
    /// Returns `original` with `handle` dragged to `point`.
    /// - keepAspect: ⇧ (box: keep aspect; line/arrow ends: snap to 15°).
    /// - fromCenter: ⌥ (box: resize symmetrically about the centre).
    static func apply(
        _ handle: Handle.Kind, to original: AnnotationObject, dragTo point: CGPoint,
        keepAspect: Bool, fromCenter: Bool
    ) -> AnnotationObject {
        var object = original
        switch original.shape {
        case .arrow(var g):
            switch handle {
            case .start: g.start = keepAspect ? snapAngle(point, around: g.end) : point
            case .end: g.end = keepAspect ? snapAngle(point, around: g.start) : point
            case .control: g.control = point
            default: break
            }
            object.shape = .arrow(g)
        case .line(var s, var e):
            switch handle {
            case .start: s = keepAspect ? snapAngle(point, around: e) : point
            case .end: e = keepAspect ? snapAngle(point, around: s) : point
            default: break
            }
            object.shape = .line(start: s, end: e)
        case .rectangle(let r, let radius):
            object.shape = .rectangle(resize(r, handle, point, keepAspect, fromCenter), cornerRadius: radius)
        case .ellipse(let r):
            object.shape = .ellipse(resize(r, handle, point, keepAspect, fromCenter))
        case .redact(let r, let mode):
            object.shape = .redact(resize(r, handle, point, keepAspect, fromCenter), mode)
        case .highlight(.rect(let r)):
            object.shape = .highlight(.rect(resize(r, handle, point, keepAspect, fromCenter)))
        case .counter(var c):
            if handle == .tail { c.tail = point }
            object.shape = .counter(c)
        case .text(var box):
            let frame = AnnotationRenderer.bounds(of: original)
            switch handle {
            case .left, .right:
                // Side handles set the wrap width.
                let r = resize(frame, handle, point, false, fromCenter)
                let pad = frame.width - textWidth(original)
                box.wrapWidth = max(r.width - pad, original.style.fontSize)
                box.origin.x += r.minX - frame.minX
            case .topLeft, .topRight, .bottomLeft, .bottomRight, .top, .bottom:
                // Corner handles scale the font.
                let r = resize(frame, handle, point, true, fromCenter)
                let factor = max(r.height / max(frame.height, 1), 0.05)
                object.style.fontSize = max(original.style.fontSize * factor, 4)
                box.wrapWidth = box.wrapWidth.map { $0 * factor }
                box.origin = CGPoint(
                    x: r.minX + (box.origin.x - frame.minX) * factor,
                    y: r.minY + (box.origin.y - frame.minY) * factor
                )
            default: break
            }
            object.shape = .text(box)
        case .highlight(.freehand(let pts)):
            object.shape = .highlight(.freehand(scalePoints(pts, original, handle, point, keepAspect, fromCenter)))
        case .pen(let pts):
            object.shape = .pen(scalePoints(pts, original, handle, point, keepAspect, fromCenter))
        }
        return object
    }

    /// Width of the text content (bounds minus stroke padding).
    private static func textWidth(_ object: AnnotationObject) -> CGFloat {
        AnnotationRenderer.bounds(of: object).width - 2 * object.style.lineWidth
    }

    private static func scalePoints(
        _ pts: [CGPoint], _ original: AnnotationObject, _ handle: Handle.Kind, _ point: CGPoint,
        _ keepAspect: Bool, _ fromCenter: Bool
    ) -> [CGPoint] {
        let frame = AnnotationRenderer.bounds(of: original)
        let r = resize(frame, handle, point, keepAspect, fromCenter)
        let sx = r.width / max(frame.width, 1), sy = r.height / max(frame.height, 1)
        return pts.map { CGPoint(x: r.minX + ($0.x - frame.minX) * sx, y: r.minY + ($0.y - frame.minY) * sy) }
    }

    /// Point snapped so the segment from `anchor` is a multiple of 15°.
    static func snapAngle(_ point: CGPoint, around anchor: CGPoint) -> CGPoint {
        let dx = point.x - anchor.x, dy = point.y - anchor.y
        let length = hypot(dx, dy)
        guard length > 0 else { return point }
        let step = CGFloat.pi / 12
        let angle = (atan2(dy, dx) / step).rounded() * step
        return CGPoint(x: anchor.x + cos(angle) * length, y: anchor.y + sin(angle) * length)
    }

    /// Box resize. The result is standardized (dragging past the opposite edge flips).
    static func resize(
        _ rect: CGRect, _ handle: Handle.Kind, _ p: CGPoint, _ keepAspect: Bool, _ fromCenter: Bool
    ) -> CGRect {
        let r = rect.standardized
        var minX = r.minX, maxX = r.maxX, minY = r.minY, maxY = r.maxY
        let movesLeft = [.topLeft, .left, .bottomLeft].contains(handle)
        let movesRight = [.topRight, .right, .bottomRight].contains(handle)
        let movesTop = [.topLeft, .top, .topRight].contains(handle)
        let movesBottom = [.bottomLeft, .bottom, .bottomRight].contains(handle)
        if movesLeft { minX = p.x }
        if movesRight { maxX = p.x }
        if movesTop { minY = p.y }
        if movesBottom { maxY = p.y }
        if fromCenter {
            if movesLeft { maxX = r.midX + (r.midX - minX) }
            if movesRight { minX = r.midX - (maxX - r.midX) }
            if movesTop { maxY = r.midY + (r.midY - minY) }
            if movesBottom { minY = r.midY - (maxY - r.midY) }
        }
        var out = CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        let isCorner = (movesLeft || movesRight) && (movesTop || movesBottom)
        if keepAspect, isCorner, r.width > 0, r.height > 0 {
            let aspect = r.width / r.height
            let anchor = fromCenter
                ? CGPoint(x: r.midX, y: r.midY)
                : CGPoint(x: movesLeft ? r.maxX : r.minX, y: movesTop ? r.maxY : r.minY)
            let dx = p.x - anchor.x, dy = p.y - anchor.y
            let newW = max(abs(dx), abs(dy) * aspect), newH = newW / aspect
            let sx: CGFloat = dx == 0 ? (movesLeft ? -1 : 1) : (dx < 0 ? -1 : 1)
            let sy: CGFloat = dy == 0 ? (movesTop ? -1 : 1) : (dy < 0 ? -1 : 1)
            if fromCenter {
                out = CGRect(x: anchor.x - newW, y: anchor.y - newH, width: 2 * newW, height: 2 * newH)
            } else {
                out = CGRect(x: anchor.x, y: anchor.y, width: sx * newW, height: sy * newH)
            }
        }
        return out.standardized
    }
}
