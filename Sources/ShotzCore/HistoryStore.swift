import Foundation

public protocol HistoryStore: Sendable {
    func add(_ capture: CaptureResult) async
    func recent(limit: Int) async -> [CaptureResult]
    func remove(id: CaptureResult.ID, deleteFile: Bool) async
    /// The editor's editable document for this capture (JSON; may not exist yet).
    func documentURL(for id: CaptureResult.ID) -> URL
    /// Where the editor writes the flattened annotated PNG for this capture
    /// (next to the document; may not exist). Removed with the capture.
    func renderedURL(for id: CaptureResult.ID) -> URL
    /// The last export written for this capture (stack Save, auto-save or the
    /// editor's Save), or nil if it was never exported or that file is gone.
    /// The editor's Save overwrites this file instead of making a new one.
    func exportURL(for id: CaptureResult.ID) async -> URL?
    /// Records where a capture was just exported; persists across launches.
    func markExported(id: CaptureResult.ID, url: URL) async
}
