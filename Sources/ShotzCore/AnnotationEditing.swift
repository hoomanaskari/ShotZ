import Foundation

/// The editor. Implemented by AnnotationEditor.
@MainActor public protocol AnnotationEditing: AnyObject {
    /// Told when an editor window for a capture closes (SPEC §4.6).
    var delegate: AnnotationEditingDelegate? { get set }
    func openEditor(for capture: CaptureResult)
    func openEditor(imageAt url: URL)
}

/// Receives editor closes. Implemented by `AppCoordinator`.
@MainActor public protocol AnnotationEditingDelegate: AnyObject {
    /// An editor window for `capture` closed (⌘W, close button, or "close
    /// after copy/save"). Not called for images opened from a file, nor when
    /// Shotz quits.
    /// - Parameters:
    ///   - renderedImageURL: a flattened full-resolution PNG of the document
    ///     (at `HistoryStore.renderedURL(for:)`), written before this call,
    ///     when the document has edits (objects, crop or background); nil when
    ///     it has none.
    ///   - displayID: the `CGDirectDisplayID` the window was on, if known.
    func editor(didClose capture: CaptureResult, renderedImageURL: URL?, onDisplay displayID: UInt32?)
}
