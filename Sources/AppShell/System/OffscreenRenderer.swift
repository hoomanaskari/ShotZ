import AppKit

/// Renders a real, fully built window to PNG for `--debug-snapshot-ui`,
/// without ever ordering it on screen: reviewing UI never pops a window over
/// the user's work or activates Shotz. Captures the theme frame, so the title
/// bar, toolbar and window background are included.
@MainActor enum OffscreenRenderer {
    static func capture(_ window: NSWindow) async -> Data? {
        window.contentView?.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first update passes; a cancelled sleep only shortens the wait.
        try? await Task.sleep(for: .milliseconds(450))
        guard let frameView = window.contentView?.superview else { return nil }
        frameView.layoutSubtreeIfNeeded()
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
