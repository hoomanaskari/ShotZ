import AppKit

/// The live `KeyFocusHost`: makes the hovered card's panel key without
/// activating Shotz, and gives focus back to the app the user was in.
extension QuickAccessController: KeyFocusHost {
    func takeKey() {
        guard let panel = hoveredCard?.window as? StackPanel else { return }
        if focusOwnerBeforeHover == nil {
            focusOwnerBeforeHover = NSWorkspace.shared.frontmostApplication
        }
        panel.acceptsKey = true
        panel.makeKey()
        installKeyMonitor()
    }

    /// Re-ordering the panel (transparent, same place) drops key status; if the
    /// system then treats Shotz as frontmost, activation goes back to the app
    /// that had it before the hover.
    func relinquishKey() {
        removeKeyMonitor()
        let previous = focusOwnerBeforeHover
        focusOwnerBeforeHover = nil
        for panel in panels.values where panel.acceptsKey {
            panel.acceptsKey = false
            if panel.isKeyWindow, !quickLook.isShowing {
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
        let me = NSRunningApplication.current
        if let previous, previous != me, NSWorkspace.shared.frontmostApplication == me {
            NSApp.yieldActivation(to: previous)
            previous.activate(from: me)
        }
    }
}
