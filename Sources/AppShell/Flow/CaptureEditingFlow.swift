import os
import Foundation
import ShotzCore

/// One capture, one place on screen (SPEC §4.6): routes captures between the
/// quick-access stack and the editor using only ShotzCore protocols, so the
/// rules are unit-tested with fakes. `AppCoordinator` owns one and makes it
/// the editor's delegate.
@MainActor public final class CaptureEditingFlow: AnnotationEditingDelegate {
    private let quickAccess: QuickAccessPresenting
    private let editor: AnnotationEditing
    /// The flattened annotated PNG for a capture if one exists on disk.
    private let renderedImage: (CaptureResult.ID) -> URL?
    /// Called whenever a capture is put in the stack (e.g. to drop it from
    /// the coordinator's recently-closed list).
    public var didPresent: ((CaptureResult) -> Void)?
    private let log = ShotzLog.logger("App")

    public init(
        quickAccess: QuickAccessPresenting,
        editor: AnnotationEditing,
        renderedImage: @escaping (CaptureResult.ID) -> URL?
    ) {
        self.quickAccess = quickAccess
        self.editor = editor
        self.renderedImage = renderedImage
    }

    /// Makes this flow the editor's delegate (closes return the card).
    public func attach(to editor: AnnotationEditing) {
        editor.delegate = self
    }

    /// Opens a capture in the editor from a card's Annotate, history or the
    /// status menu. Any card for it leaves the stack first (Annotate already
    /// removed it; `dismiss` is a no-op then and never reports a close).
    public func openInEditor(_ capture: CaptureResult) {
        quickAccess.dismiss(id: capture.id)
        editor.openEditor(for: capture)
    }

    /// Puts a capture in the stack (new capture, history, restore): shows the
    /// annotated render when the capture has one.
    public func presentInStack(_ capture: CaptureResult) {
        present(capture, imageURL: renderedImage(capture.id))
    }

    // MARK: AnnotationEditingDelegate

    /// Closing the editor returns the card as the newest one, on the editor's
    /// display, showing the annotated result when there are edits.
    public func editor(didClose capture: CaptureResult, renderedImageURL: URL?, onDisplay displayID: UInt32?) {
        let placed = displayID.map(capture.onDisplay) ?? capture
        log.info("Editor closed for \(capture.displayName, privacy: .private); returning card (\(renderedImageURL == nil ? "original" : "annotated", privacy: .public))")
        present(placed, imageURL: renderedImageURL)
    }

    private func present(_ capture: CaptureResult, imageURL: URL?) {
        quickAccess.present(capture, imageURL: imageURL)
        didPresent?(capture)
    }
}
