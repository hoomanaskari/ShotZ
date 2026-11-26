import Foundation

@MainActor public protocol QuickAccessDelegate: AnyObject {
    func quickAccess(requestAnnotate capture: CaptureResult)
    func quickAccess(didClose capture: CaptureResult, deleteFile: Bool)
    func quickAccess(didExport capture: CaptureResult, to url: URL)
}
