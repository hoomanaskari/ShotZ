import AppKit

/// Window for the shell's own windows. Shotz is an agent app without a main
/// menu, so standard key equivalents have to be handled here: ⌘W closes, and
/// ⌘1…⌘9 select a tab when `onSelectIndex` is set.
final class ShellWindow: NSWindow {
    var onSelectIndex: ((Int) -> Void)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command, let key = event.charactersIgnoringModifiers?.lowercased() {
            if key == "w" {
                performClose(nil)
                return true
            }
            if let onSelectIndex, let n = Int(key), (1...9).contains(n) {
                onSelectIndex(n - 1)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
