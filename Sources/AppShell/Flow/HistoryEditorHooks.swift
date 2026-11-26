import Foundation
import ShotzCore

/// The closures `EditorCoordinator` takes, all backed by the history store, so
/// AppCoordinator wires them in one place and tests can check them.
public struct HistoryEditorHooks: Sendable {
    public let documentURL: @Sendable (CaptureResult.ID) -> URL
    public let renderedURL: @Sendable (CaptureResult.ID) -> URL
    public let previousExport: @Sendable (CaptureResult.ID) async -> URL?
    public let recordExport: @Sendable (CaptureResult.ID, URL) async -> Void

    public init(history: FileHistoryStore) {
        documentURL = { history.documentURL(for: $0) }
        renderedURL = { history.renderedURL(for: $0) }
        previousExport = { await history.exportURL(for: $0) }
        recordExport = { await history.markExported(id: $0, url: $1) }
    }
}
