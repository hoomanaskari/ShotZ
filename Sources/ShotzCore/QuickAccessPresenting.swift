/// The overlay. Implemented by QuickAccess.
@MainActor public protocol QuickAccessPresenting: AnyObject {
    var delegate: QuickAccessDelegate? { get set }
    func present(_ capture: CaptureResult)
    func dismiss(id: CaptureResult.ID)
    func dismissAll()
}
