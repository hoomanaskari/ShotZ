import ShotzCore
import Foundation

/// Debug-only launch arguments for exercising features without Screen Recording:
/// `--debug-present <png> [<png>...]`, `--debug-edit <png>` and
/// `--debug-snapshot-ui <dir>` (renders Settings/onboarding/status item to PNGs).
struct DebugLaunchArguments: Equatable {
    var present: [URL] = []
    var edit: URL?
    var snapshotUI: URL?
    /// `--debug-edit-capture <png>`: import into history (or reuse) and open with `openEditor(for:)`.
    var editCapture: URL?
    /// `--debug-capture-id <uuid>`: forces the history id used by `--debug-edit-capture`.
    var captureID: UUID?

    var isEmpty: Bool { present.isEmpty && edit == nil && snapshotUI == nil && editCapture == nil }

    init(
        arguments: [String] = Array(DebugHooks.arguments.dropFirst()),   // empty in the production app
        currentDirectory: URL = URL(filePath: FileManager.default.currentDirectoryPath, directoryHint: .isDirectory)
    ) {
        func url(_ path: String) -> URL {
            URL(filePath: path, directoryHint: .notDirectory, relativeTo: currentDirectory).standardizedFileURL
        }
        var i = arguments.startIndex
        while i < arguments.endIndex {
            switch arguments[i] {
            case "--debug-present":
                i += 1
                while i < arguments.endIndex, !arguments[i].hasPrefix("-") {
                    present.append(url(arguments[i]))
                    i += 1
                }
            case "--debug-edit":
                i += 1
                if i < arguments.endIndex, !arguments[i].hasPrefix("-") {
                    edit = url(arguments[i])
                    i += 1
                }
            case "--debug-edit-capture":
                i += 1
                if i < arguments.endIndex, !arguments[i].hasPrefix("-") {
                    editCapture = url(arguments[i])
                    i += 1
                }
            case "--debug-capture-id":
                i += 1
                if i < arguments.endIndex {
                    captureID = UUID(uuidString: arguments[i])
                    i += 1
                }
            case "--debug-snapshot-ui":
                i += 1
                if i < arguments.endIndex, !arguments[i].hasPrefix("-") {
                    snapshotUI = URL(filePath: arguments[i], directoryHint: .isDirectory, relativeTo: currentDirectory).standardizedFileURL
                    i += 1
                }
            default:
                i += 1
            }
        }
    }
}
