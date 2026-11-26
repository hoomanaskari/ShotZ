import Foundation

/// The overlay. Implemented by QuickAccess.
///
/// Card lifecycle (SPEC §4.4, §4.6):
/// - `present` adds the capture as the newest card (replacing a card for the
///   same capture id). It is placed by `capture.displayID` per the display
///   setting; the coordinator passes `capture.onDisplay(_:)` to place a card
///   returning from the editor on the editor's display.
/// - Annotate removes the card and calls `quickAccess(requestAnnotate:)`; it
///   does NOT call `quickAccess(didClose:)` (the capture is still in use). The
///   coordinator presents it again when the editor closes.
/// - `dismiss(id:)` / `dismissAll()` remove cards programmatically and never
///   call `didClose`; `didClose` is only for closes the user (or a stack
///   setting such as auto-close or eviction) caused.
@MainActor public protocol QuickAccessPresenting: AnyObject {
    var delegate: QuickAccessDelegate? { get set }
    /// - Parameter imageURL: the image the card shows and delivers (thumbnail,
    ///   size caption, Copy, Save, Quick Look, drag-out), e.g. the flattened
    ///   annotated render; nil means `capture.fileURL`.
    func present(_ capture: CaptureResult, imageURL: URL?)
    func dismiss(id: CaptureResult.ID)
    func dismissAll()
}

extension QuickAccessPresenting {
    /// Presents the capture's own image.
    public func present(_ capture: CaptureResult) {
        present(capture, imageURL: nil)
    }
}
