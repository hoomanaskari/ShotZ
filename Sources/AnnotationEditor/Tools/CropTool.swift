import AnnotationKit
import CoreGraphics
import Foundation

/// C: non-destructive crop. The draft (`EditorModel.cropDraft`) starts from the
/// current crop over the full image, so a crop can be re-opened and widened.
/// Return applies, Esc cancels. Edges snap to image edges and objects.
@MainActor final class CropTool: Tool, ModelBound {
    let kind = ToolKind.crop
    weak var model: EditorModel?

    private enum Drag {
        case handle(Handle.Kind, original: CGRect)
        case move(original: CGRect, start: CGPoint)
        case create(start: CGPoint)
    }

    private var drag: Drag?

    func activate() {
        guard let model else { return }
        if model.textHost?.isEditingText == true { model.textHost?.endEditing() }
        model.clearSelection()
        model.cropDraft = model.document.crop ?? model.imageBounds
    }

    func deactivate() {
        model?.cropDraft = nil
        model?.guides = []
    }

    // MARK: Mouse

    func mouseDown(_ event: ToolEvent) {
        guard let model, let draft = model.cropDraft else { return }
        if let handle = Self.handle(at: event.point, of: draft, radius: 8 / max(model.pointsPerPixel, 0.0001)) {
            drag = .handle(handle, original: draft)
        } else if draft.contains(event.point) {
            drag = .move(original: draft, start: event.point)
        } else {
            drag = .create(start: clamp(event.point))
        }
    }

    func mouseDragged(_ event: ToolEvent) {
        guard let model, let drag else { return }
        let bounds = model.imageBounds
        let ratio = model.cropAspect.ratio(imageSize: model.document.pixelSize)
        switch drag {
        case .handle(let kind, let original):
            let p = clamp(model.snapPoint(event.point, excluding: [], modifiers: event.modifiers))
            var r = HandleGeometryShim.resize(original, kind, p, ratio != nil, event.modifiers.contains(.option))
            if let ratio { r = Self.constrain(r, ratio: ratio, handle: kind) }
            model.cropDraft = Self.clipped(r, ratio: ratio, to: bounds)
        case .move(let original, let start):
            var r = original.offsetBy(dx: event.point.x - start.x, dy: event.point.y - start.y)
            let snap = model.snapOffset(for: r, excluding: [], modifiers: event.modifiers)
            r = r.offsetBy(dx: snap.dx, dy: snap.dy)
            r.origin.x = min(max(r.minX, bounds.minX), bounds.maxX - r.width)
            r.origin.y = min(max(r.minY, bounds.minY), bounds.maxY - r.height)
            model.cropDraft = r.integral
        case .create(let start):
            let p = clamp(model.snapPoint(event.point, excluding: [], modifiers: event.modifiers))
            var r = CGRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
            if let ratio {
                let h = r.width / ratio
                r = CGRect(x: r.minX, y: p.y < start.y ? start.y - h : start.y, width: r.width, height: h)
            }
            if r.width >= 1, r.height >= 1 { model.cropDraft = Self.clipped(r, ratio: ratio, to: bounds) }
        }
    }

    func mouseUp(_ event: ToolEvent) {
        drag = nil
        model?.guides = []
    }

    func keyDown(_ key: ToolKey) -> Bool {
        switch key {
        case .returnKey:
            apply()
            return true
        case .escape:
            model?.setTool(.select)
            return true
        default:
            return false
        }
    }

    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor {
        guard let model, let draft = model.cropDraft else { return .crosshair }
        if let h = Self.handle(at: point, of: draft, radius: 8 / max(model.pointsPerPixel, 0.0001)) {
            let c = CGPoint(x: draft.midX, y: draft.midY)
            let p = Self.position(of: h, in: draft)
            return .resize(angle: atan2(p.y - c.y, p.x - c.x))
        }
        return draft.contains(point) ? .move : .crosshair
    }

    // MARK: Commands

    /// Return: writes the crop (nil when it covers the whole image), back to Select.
    func apply() {
        guard let model, let draft = model.cropDraft else { return }
        let full = model.imageBounds
        let crop = draft.integral.intersection(full)
        let value: CGRect? = (crop == full || crop.width < 1 || crop.height < 1) ? nil : crop
        model.store.perform(String(localized: "Crop")) { $0.crop = value }
        model.setTool(.select)
    }

    /// Aspect preset changed: fit the draft to it, centred.
    func applyAspect() {
        guard let model, let draft = model.cropDraft,
              let ratio = model.cropAspect.ratio(imageSize: model.document.pixelSize) else { return }
        model.cropDraft = CropAspect.fit(draft, ratio: ratio, within: model.imageBounds).integral
    }

    /// Numeric W×H fields.
    func setSize(width: CGFloat?, height: CGFloat?) {
        guard let model, var r = model.cropDraft else { return }
        let ratio = model.cropAspect.ratio(imageSize: model.document.pixelSize)
        let bounds = model.imageBounds
        if let width { r.size.width = min(max(width, 1), bounds.width); if let ratio { r.size.height = r.width / ratio } }
        if let height { r.size.height = min(max(height, 1), bounds.height); if let ratio { r.size.width = r.height * ratio } }
        r.size.width = min(r.width, bounds.width)
        r.size.height = min(r.height, bounds.height)
        r.origin.x = min(max(r.minX, 0), bounds.maxX - r.width)
        r.origin.y = min(max(r.minY, 0), bounds.maxY - r.height)
        model.cropDraft = r.integral
    }

    // MARK: Geometry

    /// Clips to the image, keeping the aspect lock.
    static func clipped(_ r: CGRect, ratio: CGFloat?, to bounds: CGRect) -> CGRect {
        let clipped = r.intersection(bounds)
        guard !clipped.isNull else { return r.integral }
        guard let ratio else { return clipped.integral }
        return CropAspect.fit(clipped, ratio: ratio, within: bounds).integral
    }

    private func clamp(_ p: CGPoint) -> CGPoint {
        guard let b = model?.imageBounds else { return p }
        return CGPoint(x: min(max(p.x, b.minX), b.maxX), y: min(max(p.y, b.minY), b.maxY))
    }

    static let handleKinds: [Handle.Kind] = [.topLeft, .top, .topRight, .right, .bottomRight, .bottom, .bottomLeft, .left]

    static func position(of kind: Handle.Kind, in r: CGRect) -> CGPoint {
        switch kind {
        case .topLeft: CGPoint(x: r.minX, y: r.minY)
        case .top: CGPoint(x: r.midX, y: r.minY)
        case .topRight: CGPoint(x: r.maxX, y: r.minY)
        case .right: CGPoint(x: r.maxX, y: r.midY)
        case .bottomRight: CGPoint(x: r.maxX, y: r.maxY)
        case .bottom: CGPoint(x: r.midX, y: r.maxY)
        case .bottomLeft: CGPoint(x: r.minX, y: r.maxY)
        default: CGPoint(x: r.minX, y: r.midY)
        }
    }

    static func handle(at p: CGPoint, of r: CGRect, radius: CGFloat) -> Handle.Kind? {
        handleKinds.first { k in
            let h = position(of: k, in: r)
            return hypot(h.x - p.x, h.y - p.y) <= radius
        }
    }

    /// Side handles under an aspect lock adjust the other dimension about the centre.
    static func constrain(_ r: CGRect, ratio: CGFloat, handle: Handle.Kind) -> CGRect {
        switch handle {
        case .left, .right:
            let h = r.width / ratio
            return CGRect(x: r.minX, y: r.midY - h / 2, width: r.width, height: h)
        case .top, .bottom:
            let w = r.height * ratio
            return CGRect(x: r.midX - w / 2, y: r.minY, width: w, height: r.height)
        default:
            // Corners: keepAspect in `resize` preserved the original's ratio; enforce the preset.
            let w = r.width, h = w / ratio
            return CGRect(x: r.minX, y: handle == .topLeft || handle == .topRight ? r.maxY - h : r.minY, width: w, height: h)
        }
    }
}
