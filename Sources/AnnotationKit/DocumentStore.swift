import Combine
import Foundation

/// Reference type owning a document plus snapshot-based undo history. Main-actor.
@MainActor public final class DocumentStore: ObservableObject {
    private struct Snapshot {
        let name: String
        let document: AnnotationDocument
    }

    @Published public private(set) var document: AnnotationDocument

    private var undoStack: [Snapshot] = []
    private var redoStack: [Snapshot] = []
    private var interactive: (name: String, base: AnnotationDocument)?
    private var continuations: [UUID: AsyncStream<DocumentChange>.Continuation] = [:]

    public init(document: AnnotationDocument) {
        self.document = document
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }
    /// For "Undo <name>" menu titles.
    public var undoActionName: String? { undoStack.last?.name }
    public var redoActionName: String? { redoStack.last?.name }
    public var isInteractive: Bool { interactive != nil }

    /// One undoable change. A change that leaves the document equal is not recorded.
    public func perform(_ name: String, _ change: (inout AnnotationDocument) -> Void) {
        if interactive != nil { commitInteractiveChange() }
        let before = document
        var after = before
        change(&after)
        guard after != before else { return }
        undoStack.append(Snapshot(name: name, document: before))
        redoStack.removeAll()
        apply(after, from: before, reason: .perform(name))
    }

    /// Starts a drag-style change: many updates, one undo step.
    public func beginInteractiveChange(_ name: String) {
        if interactive != nil { commitInteractiveChange() }
        interactive = (name, document)
    }

    public func updateInteractive(_ change: (inout AnnotationDocument) -> Void) {
        guard let interactive else {
            assertionFailure("updateInteractive without beginInteractiveChange")
            return
        }
        let before = document
        var after = before
        change(&after)
        guard after != before else { return }
        apply(after, from: before, reason: .interactive(interactive.name))
    }

    public func commitInteractiveChange() {
        guard let (name, base) = interactive else { return }
        interactive = nil
        guard document != base else { return }
        undoStack.append(Snapshot(name: name, document: base))
        redoStack.removeAll()
    }

    public func cancelInteractiveChange() {
        guard let (name, base) = interactive else { return }
        interactive = nil
        apply(base, from: document, reason: .interactive(name))
    }

    public func undo() {
        if interactive != nil { cancelInteractiveChange() }
        guard let snap = undoStack.popLast() else { return }
        redoStack.append(Snapshot(name: snap.name, document: document))
        apply(snap.document, from: document, reason: .undo)
    }

    public func redo() {
        if interactive != nil { cancelInteractiveChange() }
        guard let snap = redoStack.popLast() else { return }
        undoStack.append(Snapshot(name: snap.name, document: document))
        apply(snap.document, from: document, reason: .redo)
    }

    /// Replaces the document and clears history (e.g. after loading).
    public func replaceDocument(_ new: AnnotationDocument) {
        interactive = nil
        undoStack.removeAll()
        redoStack.removeAll()
        apply(new, from: document, reason: .replace)
    }

    /// A new stream per subscriber; ends when the store is deallocated.
    public var changes: AsyncStream<DocumentChange> {
        let (stream, continuation) = AsyncStream<DocumentChange>.makeStream(bufferingPolicy: .unbounded)
        let token = UUID()
        continuations[token] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { @MainActor in self?.continuations[token] = nil }
        }
        return stream
    }

    private func apply(_ new: AnnotationDocument, from old: AnnotationDocument, reason: DocumentChange.Reason) {
        document = new
        let change = DocumentChange.between(old, new, reason: reason)
        for c in continuations.values { c.yield(change) }
    }

    isolated deinit {
        for c in continuations.values { c.finish() }
    }
}
