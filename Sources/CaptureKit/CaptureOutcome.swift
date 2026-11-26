import ShotzCore

/// Maps what `screencapture` left behind to a result (pure; unit-tested).
enum CaptureOutcome: Equatable {
    case image
    case cancelled
    case failure(CaptureError)

    /// - Parameters:
    ///   - fileExists: whether the tool wrote a non-empty output file.
    ///   - hasPermission: consulted only when the answer depends on it.
    static func classify(status: Int32, stderr: String, fileExists: Bool, hasPermission: () -> Bool) -> CaptureOutcome {
        if fileExists {
            // Without Screen Recording the tool still succeeds but produces a
            // wallpaper-only image (SPEC §8: show the permission step instead).
            return hasPermission() ? .image : .failure(.permissionDenied)
        }
        let message = stderr.lowercased()
        if message.contains("two interactive") || message.contains("already running") {
            return .failure(.busy)
        }
        // Esc / click-away: the tool exits (status 0 or 1) quietly with no file.
        if message.isEmpty { return .cancelled }
        if !hasPermission() { return .failure(.permissionDenied) }
        return .failure(.failed(stderr))
    }

    /// Kind of a finished capture. Interactive modes cannot tell us whether the
    /// user pressed Space for a window; window captures carry an alpha channel
    /// (transparent shadow/corners) while area and screen captures do not.
    static func kind(for mode: CaptureMode, hasAlpha: Bool) -> CaptureKind {
        switch mode {
        case .fullscreen: .fullscreen
        case .window: .window
        case .area, .allInOne: hasAlpha ? .window : .area
        }
    }
}
