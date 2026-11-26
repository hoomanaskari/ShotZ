import AppKit

extension ShotzUI {
    /// When ShotZ shows a focus ring: only for keyboard navigation.
    ///
    /// - A pointer click never moves keyboard focus, so it never leaves a ring (AppKit controls refuse
    ///   first responder during mouse events; SwiftUI controls are buttons, which only keyboard
    ///   navigation focuses).
    /// - Focus that arrives by key-view navigation (Tab, ⇧Tab, Full Keyboard Access) shows the ring.
    /// - Focus given any other way (a window opening, code) is kept, for typing and accessibility,
    ///   but shows no ring until the keyboard moves it. Clicking a keyboard-focused control hides
    ///   its ring; it stays focused.
    @MainActor
    public enum FocusRing {
        /// The event that is moving focus. A seam for tests, which deliver events to windows directly.
        static var currentEvent: () -> NSEvent? = { NSApp.currentEvent }
        /// Whether a window draws focus as active. A seam for tests and off-screen renders (a window
        /// that is never shown is never key).
        static var isKeyWindow: (NSWindow) -> Bool = { $0.isKeyWindow }

        /// Pointer events: clicks (any button) and drags.
        public static func isPointer(_ event: NSEvent?) -> Bool {
            guard let event else { return false }
            switch event.type {
            case .leftMouseDown, .leftMouseUp, .leftMouseDragged, .rightMouseDown, .rightMouseUp, .rightMouseDragged,
                 .otherMouseDown, .otherMouseUp, .otherMouseDragged:
                return true
            default:
                return false
            }
        }

        /// Key-view navigation: Tab with or without ⇧ / ⌃ (the keys AppKit and Full Keyboard Access
        /// use to move focus between controls).
        public static func isKeyViewNavigation(_ event: NSEvent?) -> Bool {
            guard let event, event.type == .keyDown else { return false }
            return event.keyCode == 48 // kVK_Tab
        }

        /// Clears keyboard focus when a window is about to show, so it never opens with a ring on its
        /// first control (Tab then starts from the first control). Text being edited keeps focus.
        public static func clearOpeningFocus(in window: NSWindow) {
            if window.firstResponder is NSText { return }
            if window.firstResponder !== window { window.makeFirstResponder(nil) }
        }
    }
}
