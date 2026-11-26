import AnnotationKit
import AppKit

/// Annotation objects on the general pasteboard (AnnotationKit's format), so
/// ⌘C/⌘V work between editor windows. Placement is pure and unit-tested.
@MainActor enum ObjectPasteboard {
    static let type = NSPasteboard.PasteboardType(AnnotationPasteboard.typeIdentifier)

    static func write(_ objects: [AnnotationObject], to pb: NSPasteboard = .general) throws {
        let data = try AnnotationPasteboard.encode(objects)
        pb.clearContents()
        pb.setData(data, forType: type)
    }

    static func read(from pb: NSPasteboard = .general) -> [AnnotationObject] {
        pb.data(forType: type).map(AnnotationPasteboard.decode) ?? []
    }

    static var hasObjects: Bool { NSPasteboard.general.availableType(from: [type]) != nil }

    /// Where to paste: offset copies that would land exactly on existing
    /// objects, and bring objects that fall outside the target image into view.
    static func placementOffset(for objects: [AnnotationObject], in document: AnnotationDocument, step: CGFloat) -> CGVector {
        let union = objects.map(ObjectGeometry.frame(of:)).reduce(CGRect.null) { $0.union($1) }
        guard !union.isNull else { return .zero }
        let visible = document.imageRect
        var offset = CGVector.zero
        if !visible.intersects(union) {
            offset = CGVector(dx: visible.midX - union.midX, dy: visible.midY - union.midY)
        }
        let existing = Set(document.objects.map { ObjectGeometry.frame(of: $0) })
        var tries = 0
        while tries < 20, objects.contains(where: { existing.contains(ObjectGeometry.frame(of: $0).offsetBy(dx: offset.dx, dy: offset.dy)) }) {
            offset.dx += step
            offset.dy += step
            tries += 1
        }
        return offset
    }
}
