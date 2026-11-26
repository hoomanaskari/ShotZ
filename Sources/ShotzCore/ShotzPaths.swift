import Foundation

/// Shared on-disk locations. Inject a custom root in tests.
public struct ShotzPaths: Sendable, Equatable {
    /// `~/Library/Application Support/com.pixelforty.shotz` (`com.pixelforty.shotz.dev`
    /// for the development app, `<bundle id>.testrun` for test runs)
    public let root: URL
    /// Folder name under the temporary directory for scratch files.
    public let scratchName: String

    public init(root: URL, scratchName: String = AppVariant.production.dataDirectoryName) {
        self.root = root
        self.scratchName = scratchName
    }

    /// The paths for this app and run (see `AppVariant`).
    public static let `default` = forVariant(.current, testRun: AppVariant.isTestRun)

    public static func forVariant(_ variant: AppVariant, testRun: Bool = false) -> ShotzPaths {
        let name = testRun ? variant.testRunDirectoryName : variant.dataDirectoryName
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

    /// Creates `root`, `captures` and `documents` if missing, owner-only (0700; see `PrivateStorage`).
    public func createDirectories() throws {
        for dir in [root, captures, documents] {
            try PrivateStorage.makeDirectory(dir)
        }
    }

    /// Once at launch, off the main thread: tightens an existing data folder to 0700 folders and
    /// 0600 files (installs from before 0.1.2 were 0755/0644), and the temp folders to 0700.
    public func repairPermissions() -> Int {
        PrivateStorage.repair(root: root) + PrivateStorage.repair(root: temporary, files: false)
    }
}
