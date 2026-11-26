import AppKit

/// Renders a real, fully built window to PNG for `--debug-snapshot-ui`,
/// without ever ordering it on screen: reviewing UI never pops a window over
/// the user's work or activates Shotz. Captures the theme frame, so the title
/// bar, toolbar and window background are included.
@MainActor enum OffscreenRenderer {
    /// `scale` 1 or 2 renders at that pixel density regardless of the display.
    static func capture(_ window: NSWindow, scale: CGFloat = 2) async -> Data? {
        window.contentView?.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first update passes; a cancelled sleep only shortens the wait.
        try? await Task.sleep(for: .milliseconds(450))
        guard let frameView = window.contentView?.superview else { return nil }
        frameView.layoutSubtreeIfNeeded()
        let bounds = frameView.bounds
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = bounds.size
        frameView.cacheDisplay(in: bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
