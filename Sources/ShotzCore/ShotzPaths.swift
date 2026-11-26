import Foundation

/// Shared on-disk locations. Inject a custom root in tests.
public struct ShotzPaths: Sendable, Equatable {
    /// `~/Library/Application Support/Shotz` (`Shotz-Dev` in the dev profile)
    public let root: URL
    /// Folder name under the temporary directory for scratch files.
    public let scratchName: String

    public init(root: URL, scratchName: String = DevProfile.standardDirectoryName) {
        self.root = root
        self.scratchName = scratchName
    }

    /// The paths for this run: `Shotz-Dev` in the dev profile (see `DevProfile`).
    public static let `default` = forProfile(dev: DevProfile.isActive)

    public static func forProfile(dev: Bool) -> ShotzPaths {
        let name = dev ? DevProfile.directoryName : DevProfile.standardDirectoryName
        return ShotzPaths(root: URL.applicationSupportDirectory.appending(path: name, directoryHint: .isDirectory),
                          scratchName: name)
    }

    /// Private lossless originals.
    public var captures: URL { root.appending(path: "Captures", directoryHint: .isDirectory) }
    /// Editable annotation documents, one JSON per capture id.
    public var documents: URL { root.appending(path: "Documents", directoryHint: .isDirectory) }
    /// History index file.
    public var historyIndex: URL { root.appending(path: "history.json", directoryHint: .notDirectory) }
    /// Scratch area for drag-out files and in-flight captures.
    public var temporary: URL {
        FileManager.default.temporaryDirectory.appending(path: scratchName, directoryHint: .isDirectory)
    }
    public var dragExports: URL { temporary.appending(path: "Drag", directoryHint: .isDirectory) }

    /// Default export folder (`~/Desktop`).
    public static var defaultExportFolder: URL { URL.desktopDirectory }

    /// Creates `root`, `captures` and `documents` if missing.
    public func createDirectories() throws {
        let fm = FileManager.default
        for dir in [root, captures, documents] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
