import Foundation

/// Debug-only launch arguments for exercising features without Screen Recording:
/// `--debug-present <png> [<png>...]`, `--debug-edit <png>` and
/// `--debug-snapshot-ui <dir>` (renders Settings/onboarding/status item to PNGs).
struct DebugLaunchArguments: Equatable {
    var present: [URL] = []
    var edit: URL?
    var snapshotUI: URL?

    var isEmpty: Bool { present.isEmpty && edit == nil && snapshotUI == nil }

    init(
        arguments: [String] = Array(ProcessInfo.processInfo.arguments.dropFirst()),
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
