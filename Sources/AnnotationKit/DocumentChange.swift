import Foundation

/// What changed between two document states. Emitted by `DocumentStore.changes`.
public struct DocumentChange: Sendable, Equatable {
    public enum Reason: Sendable, Equatable {
        case perform(String)
        case interactive(String)
        case undo
        case redo
        case replace
    }

    public var reason: Reason
    public var added: Set<AnnotationObject.ID>
    public var removed: Set<AnnotationObject.ID>
    /// Existing objects whose shape or style changed.
    public var modified: Set<AnnotationObject.ID>
    /// z-order changed.
    public var reordered: Bool
    /// crop, background, base image, size or scale changed.
    public var documentPropertiesChanged: Bool

    public init(
        reason: Reason,
        added: Set<AnnotationObject.ID> = [],
        removed: Set<AnnotationObject.ID> = [],
        modified: Set<AnnotationObject.ID> = [],
        reordered: Bool = false,
        documentPropertiesChanged: Bool = false
    ) {
        self.reason = reason
        self.added = added
        self.removed = removed
        self.modified = modified
        self.reordered = reordered
        self.documentPropertiesChanged = documentPropertiesChanged
    }

    /// Every object id touched (added ∪ removed ∪ modified).
    public var objectIDs: Set<AnnotationObject.ID> { added.union(removed).union(modified) }

    public var isEmpty: Bool { objectIDs.isEmpty && !reordered && !documentPropertiesChanged }

    /// Diffs two documents.
    public static func between(
        _ old: AnnotationDocument, _ new: AnnotationDocument, reason: Reason
    ) -> DocumentChange {
        let oldByID = Dictionary(old.objects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let newByID = Dictionary(new.objects.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let oldIDs = Set(oldByID.keys), newIDs = Set(newByID.keys)
        let common = oldIDs.intersection(newIDs)
        let modified = Set(common.filter { oldByID[$0] != newByID[$0] })
        let oldOrder = old.objects.map(\.id).filter(common.contains)
        let newOrder = new.objects.map(\.id).filter(common.contains)
        let props = old.baseImageURL != new.baseImageURL || old.pixelSize != new.pixelSize
            || old.scale != new.scale || old.crop != new.crop || old.background != new.background
        return DocumentChange(
            reason: reason,
            added: newIDs.subtracting(oldIDs),
            removed: oldIDs.subtracting(newIDs),
            modified: modified,
            reordered: oldOrder != newOrder,
            documentPropertiesChanged: props
        )
    }
}
