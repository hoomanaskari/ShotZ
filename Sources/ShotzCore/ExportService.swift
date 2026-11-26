import Foundation

/// Shared export behaviour (file naming, format, export folder, pasteboard).
public protocol ExportService: Sendable {
    func copyToPasteboard(imageAt url: URL) async throws
    /// Returns the written file, or nil when the user cancelled the save panel.
    func saveToExportFolder(imageAt url: URL, suggestedName: String, askDestination: Bool) async throws -> URL?
    func exportFileURLForDrag(imageAt url: URL, suggestedName: String) throws -> URL
}
