import AnnotationKit
import AppKit

/// Annotation objects on the general pasteboard, so ⌘C/⌘V work between
/// editor windows. Encoding is pure and unit-tested.
@MainActor enum ObjectPasteboard {
    static let type = NSPasteboard.PasteboardType("app.shotz.annotation-objects")

    struct Payload: Codable, Equatable {
        var objects: [AnnotationObject]
        /// Size of the source image, to place objects sensibly in a smaller one.
        var sourcePixelSize: CGSize
    }

    static func encode(_ payload: Payload) throws -> Data { try JSONEncoder().encode(payload) }
    static func decode(_ data: Data) throws -> Payload { try JSONDecoder().decode(Payload.self, from: data) }

    static func write(_ objects: [AnnotationObject], sourcePixelSize: CGSize, to pb: NSPasteboard = .general) throws {
        let data = try encode(Payload(objects: objects, sourcePixelSize: sourcePixelSize))
        pb.clearContents()
        pb.setData(data, forType: type)
    }

    static func read(from pb: NSPasteboard = .general) -> Payload? {
        guard let data = pb.data(forType: type) else { return nil }
        return try? decode(data) // A payload from an incompatible version is ignored.
    }

    static var hasObjects: Bool { NSPasteboard.general.availableType(from: [type]) != nil }

    /// Where to paste: offset copies that would land exactly on existing
    /// objects, and bring objects that fall outside the target image into view.
    static func placementOffset(for objects: [AnnotationObject], in document: AnnotationDocument, step: CGFloat) -> CGVector {
        let union = objects.map(AnnotationRenderer.bounds(of:)).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return .zero }
        let visible = document.imageRect
        var offset = CGVector.zero
        if !visible.intersects(union) {
            offset = CGVector(dx: visible.midX - union.midX, dy: visible.midY - union.midY)
        }
        let existing = Set(document.objects.map { AnnotationRenderer.bounds(of: $0) })
        var tries = 0
        while tries < 20, objects.contains(where: { existing.contains(AnnotationRenderer.bounds(of: $0).offsetBy(dx: offset.dx, dy: offset.dy)) }) {
            offset.dx += step
            offset.dy += step
            tries += 1
        }
        return offset
    }
}
