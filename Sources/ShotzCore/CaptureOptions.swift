import Foundation

public struct CaptureOptions: Sendable, Equatable {
    public var includeWindowShadow: Bool
    public var playSound: Bool
    /// Where the private PNG is written (normally `ShotzPaths.captures`).
    public var destinationDirectory: URL
    /// strftime-style pattern, see `FileNaming`.
    public var fileNamePattern: String

    public init(
        includeWindowShadow: Bool = true,
        playSound: Bool = true,
        destinationDirectory: URL = ShotzPaths.default.captures,
        fileNamePattern: String = FileNaming.defaultPattern
    ) {
        self.includeWindowShadow = includeWindowShadow
        self.playSound = playSound
        self.destinationDirectory = destinationDirectory
        self.fileNamePattern = fileNamePattern
    }
}
