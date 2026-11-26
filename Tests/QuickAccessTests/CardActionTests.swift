import AppKit
import Testing
@testable import QuickAccess

struct CardActionTests {
    func key(_ code: UInt16, _ chars: String?, _ mods: NSEvent.ModifierFlags = []) -> CardAction? {
        CardAction.forKey(keyCode: code, characters: chars, modifiers: mods)
    }

    @Test func hoverShortcuts() {
        #expect(key(8, "c", .command) == .copy)
        #expect(key(1, "s", .command) == .save)
        #expect(key(14, "e", .command) == .annotate)
        #expect(key(KeyCode.returnKey, "\r") == .annotate)
        #expect(key(KeyCode.keypadEnter, "\u{3}") == .annotate)
        #expect(key(KeyCode.space, " ") == .quickLook)
        #expect(key(13, "w", .command) == .close)
        #expect(key(KeyCode.escape, "\u{1b}") == .close)
        #expect(key(KeyCode.delete, "\u{7f}", .command) == .closeAndDelete)
    }

    @Test func layoutIndependentLetters() {
        // ⌘C on a layout where C sits on another key code.
        #expect(key(34, "c", .command) == .copy)
        #expect(key(8, "C", [.command, .capsLock]) == .copy)
    }

    @Test func ignoresOtherKeysAndModifiers() {
        #expect(key(8, "c") == nil)
        #expect(key(8, "c", [.command, .shift]) == nil)
        #expect(key(8, "c", [.command, .option]) == nil)
        #expect(key(KeyCode.space, " ", .command) == nil)
        #expect(key(KeyCode.delete, "\u{7f}") == nil)
        #expect(key(0, "a", .command) == nil)
    }

    @Test func tooltipsCarryShortcuts() {
        #expect(CardAction.copy.tooltip == "Copy (⌘C)")
        #expect(CardAction.close.tooltip == "Close (⌘W)")
        #expect(CardAction.showInFinder.tooltip == "Show in Finder")
    }
}
