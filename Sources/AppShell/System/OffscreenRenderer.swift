import AppKit
import SwiftUI

/// Renders a SwiftUI view to PNG in a window that is never ordered on
/// screen, for `--debug-snapshot-ui`: reviewing UI never pops a window over
/// the user's work or activates Shotz.
@MainActor enum OffscreenRenderer {
    static func png<V: View>(_ view: V, size: CGSize) async -> Data? {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = CGRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        hosting.layoutSubtreeIfNeeded()
        // Let SwiftUI finish its first update passes; a cancelled sleep only shortens the wait.
        try? await Task.sleep(for: .milliseconds(400))
        hosting.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { return nil }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
