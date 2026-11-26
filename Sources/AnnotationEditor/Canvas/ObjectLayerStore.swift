import os
import AnnotationKit
import QuartzCore
import ShotzCore

/// One `CALayer` per annotation object, each holding a bitmap drawn by
/// `AnnotationRenderer.draw`. Only changed objects are redrawn; an object
/// that only moved has its layer moved (no re-rasterising). Redactions live in
/// their own container beneath every other object (SPEC §5.3).
@MainActor final class ObjectLayerStore {
    private struct Entry {
        let layer: CALayer
        /// The object the bitmap was rendered from, and where.
        var rendered: AnnotationObject
        var renderedFrame: CGRect
        var rasterScale: CGFloat
    }

    /// Base-image pixel space (origin top-left). Hosts base, redactions, objects.
    let world = CALayer()
    let baseLayer = CALayer()
    private let redactionContainer = CALayer()
    private let objectContainer = CALayer()

    private let base: BaseImageProvider
    private var entries: [AnnotationObject.ID: Entry] = [:]
    private var order: [AnnotationObject.ID] = []
    private var hidden: Set<AnnotationObject.ID> = []
    /// Bitmap pixels per image pixel.
    private(set) var rasterScale: CGFloat = 1
    /// Counts bitmap renders (for performance logging and tests).
    private(set) var renderCount = 0
    private let log = ShotzLog.logger("AnnotationEditor")

    /// Largest bitmap side for one object.
    static let maxBitmapSide: CGFloat = 4096
    static let maxRasterScale: CGFloat = 4

    init(base: BaseImageProvider) {
        self.base = base
        for layer in [world, baseLayer, redactionContainer, objectContainer] {
            layer.actions = Self.noActions
            layer.anchorPoint = .zero
        }
        world.isGeometryFlipped = false
        baseLayer.minificationFilter = .trilinear
        baseLayer.magnificationFilter = .nearest
        baseLayer.contentsGravity = .resize
        world.addSublayer(baseLayer)
        world.addSublayer(redactionContainer)
        world.addSublayer(objectContainer)
    }

    static let noActions: [String: any CAAction] = [
        "position": NSNull(), "bounds": NSNull(), "frame": NSNull(), "contents": NSNull(),
        "hidden": NSNull(), "sublayers": NSNull(), "transform": NSNull(), "opacity": NSNull(),
        "onOrderIn": NSNull(), "onOrderOut": NSNull(), "contentsScale": NSNull(),
    ]

    func setBaseImage(_ image: CGImage, pixelSize: CGSize) {
        baseLayer.contents = image
        world.bounds = CGRect(origin: .zero, size: pixelSize)
        baseLayer.frame = CGRect(origin: .zero, size: pixelSize)
        redactionContainer.frame = baseLayer.frame
        objectContainer.frame = baseLayer.frame
    }

    // MARK: Sync

    /// Brings the layers in line with `document`. `changed` limits the work
    /// to those ids (nil = check everything).
    func sync(_ document: AnnotationDocument, changed: Set<AnnotationObject.ID>? = nil, rerenderRedactions: Bool = false) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }

        let ids = document.objects.map(\.id)
        let present = Set(ids)
        for id in entries.keys where !present.contains(id) {
            entries[id]?.layer.removeFromSuperlayer()
            entries[id] = nil
        }
        for object in document.objects {
            if let changed, !changed.contains(object.id), entries[object.id] != nil,
               !(rerenderRedactions && object.isRedaction) { continue }
            update(object, document: document, force: rerenderRedactions && object.isRedaction)
        }
        if ids != order {
            order = ids
            redactionContainer.sublayers = document.objects.filter(\.isRedaction).compactMap { entries[$0.id]?.layer }
            objectContainer.sublayers = document.objects.filter { !$0.isRedaction }.compactMap { entries[$0.id]?.layer }
        }
    }

    private func update(_ object: AnnotationObject, document: AnnotationDocument, force: Bool) {
        if let entry = entries[object.id] {
            if !force, entry.rendered == object, entry.rasterScale == rasterScale { return }
            if !force, entry.rasterScale == rasterScale, let d = ShapeTranslation.delta(from: entry.rendered, to: object) {
                // Moved only: shift the existing bitmap.
                entry.layer.frame = entry.renderedFrame.offsetBy(dx: d.dx, dy: d.dy)

                return
            }
            render(object, into: entry.layer, document: document)
        } else {
            let layer = CALayer()
            layer.actions = Self.noActions
            layer.anchorPoint = .zero
            if case .highlight = object.shape {
                // Multiply so the text underneath stays readable.
                layer.compositingFilter = "multiplyBlendMode"
            }
            layer.isHidden = hidden.contains(object.id)
            render(object, into: layer, document: document)
            // Placed by the order pass in `sync`.
            order = []
        }
    }

    private func render(_ object: AnnotationObject, into layer: CALayer, document: AnnotationDocument) {
        let frame = AnnotationRenderer.bounds(of: object).insetBy(dx: -2, dy: -2).integral
        guard !frame.isNull, !frame.isInfinite, frame.width > 0, frame.height > 0 else {
            layer.contents = nil
            entries[object.id] = Entry(layer: layer, rendered: object, renderedFrame: .zero, rasterScale: rasterScale)
            return
        }
        let scale = min(rasterScale, Self.maxBitmapSide / frame.width, Self.maxBitmapSide / frame.height)
        let w = max(Int((frame.width * scale).rounded(.up)), 1)
        let h = max(Int((frame.height * scale).rounded(.up)), 1)
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        guard let ctx = CGContext(
            data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            log.error("Cannot create bitmap \(w)x\(h) for object layer")
            return
        }
        // Top-left origin pixel space, as AnnotationRenderer expects.
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: CGFloat(w) / frame.width, y: -CGFloat(h) / frame.height)
        ctx.translateBy(x: -frame.minX, y: -frame.minY)
        AnnotationRenderer.draw(object, in: ctx, document: document, base: base)
        layer.contents = ctx.makeImage()
        layer.frame = frame
        renderCount += 1
        entries[object.id] = Entry(layer: layer, rendered: object, renderedFrame: frame, rasterScale: rasterScale)
    }

    // MARK: Zoom and visibility

    /// Re-rasterises every object at a new scale (after a zoom settles).
    func setRasterScale(_ scale: CGFloat, document: AnnotationDocument) {
        let s = min(max(scale, 0.05), Self.maxRasterScale)
        // Avoid churn for tiny changes.
        guard abs(s - rasterScale) / rasterScale > 0.05 else { return }
        rasterScale = s
        sync(document)
    }

    func setHidden(_ ids: Set<AnnotationObject.ID>) {
        guard ids != hidden else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, entry) in entries { entry.layer.isHidden = ids.contains(id) }
        CATransaction.commit()
        hidden = ids
    }
}
