import AppKit
import SwiftUI

/// Renders a SwiftUI view to PNG for `--debug-snapshot-ui`, the way the real
/// window looks: same window style, title bar and background, in the app's
/// current appearance. The window is never ordered on screen, so reviewing UI
/// never pops a window over the user's work or activates Shotz.
@MainActor enum OffscreenRenderer {
    struct Chrome {
        var title: String
        var styleMask: NSWindow.StyleMask
        var transparentTitlebar = false
    }

    static func png<V: View>(_ view: V, size: CGSize, chrome: Chrome) async -> Data? {
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(origin: .zero, size: size), styleMask: chrome.styleMask,
                              backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.title = chrome.title
        if chrome.transparentTitlebar {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
        window.appearance = NSApp.effectiveAppearance
        window.contentView = hosting
        window.setContentSize(size)
        // Let SwiftUI finish its first update passes; a cancelled sleep only shortens the wait.
        try? await Task.sleep(for: .milliseconds(400))
        // The theme frame (content view's superview) includes the title bar
        // and the window background; the hosting view alone is transparent.
        guard let frameView = window.contentView?.superview else { return nil }
        frameView.layoutSubtreeIfNeeded()
        defer { window.contentView = nil }
        guard let rep = frameView.bitmapImageRepForCachingDisplay(in: frameView.bounds) else { return nil }
        frameView.cacheDisplay(in: frameView.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }
}
