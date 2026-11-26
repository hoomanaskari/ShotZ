import Foundation

public protocol HistoryStore: Sendable {
    func add(_ capture: CaptureResult) async
    func recent(limit: Int) async -> [CaptureResult]
    func remove(id: CaptureResult.ID, deleteFile: Bool) async
    /// The editor's editable document for this capture (JSON; may not exist yet).
    func documentURL(for id: CaptureResult.ID) -> URL
}
