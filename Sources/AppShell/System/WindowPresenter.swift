import os
import AppKit
import ShotzCore

/// Brings a Shotz window in front of whatever the user is doing. Shotz is an
/// `LSUIElement` agent, usually inactive when a hotkey or menu item fires, so
/// relying on activation alone is not enough:
///
/// 1. The window joins the active Space (`.moveToActiveSpace`) and may sit
///    over a full-screen app (`.fullScreenAuxiliary`), so macOS never
///    switches Spaces to find it.
/// 2. `NSApp.activate()` asks to become the active app (cooperative
///    activation; a hotkey or click is user intent, so macOS normally allows it).
/// 3. `makeKeyAndOrderFront` makes it key once active, and
///    `orderFrontRegardless` puts it on top even if activation is refused.
/// The window keeps the normal level, so System Settings (opened from
/// onboarding) can come in front of it.
@MainActor public enum WindowPresenter {
    public static func prepare(_ window: NSWindow) {
        window.collectionBehavior.insert([.moveToActiveSpace, .fullScreenAuxiliary])
        window.level = .normal
        window.hidesOnDeactivate = false
    }

    public static func bringToFront(_ window: NSWindow, name: String) {
        prepare(window)
        if NSApp.isHidden { NSApp.unhide(nil) }
        if window.isMiniaturized { window.deminiaturize(nil) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        // Report the outcome on the next turn, when activation has settled.
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                let log = ShotzLog.logger("AppShell")
                if window.isKeyWindow {
                    log.info("\(name, privacy: .public) is frontmost and key")
                } else {
                    log.notice("\(name, privacy: .public) ordered front; app active: \(NSApp.isActive), visible: \(window.isVisible)")
                }
            }
        }
    }

}
