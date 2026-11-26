import AppKit
import Testing
@testable import QuickAccess
import ShotzCore

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

@MainActor
struct CardButtonTests {
    @Test(arguments: [CardSize.small, .medium, .large])
    func hitTargetsAreAtLeast28(size: CardSize) {
        let style = CardStyle(size: size)
        let chip = CardButton(action: .close, showsTitle: false, style: style)
        chip.frame = CGRect(x: 10, y: 10, width: style.chip, height: style.chip)
        #expect(chip.hitFrame.width >= 28 && chip.hitFrame.height >= 28)
        let pill = CardButton(action: .copy, showsTitle: true, style: style)
        pill.frame = CGRect(x: 0, y: 0, width: pill.pillWidth, height: style.pillHeight)
        #expect(pill.hitFrame.height >= 28)
        #expect(pill.pillWidth > style.pillHeight)
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func overlayControlsDoNotOverlap(size: CardSize) {
        let style = CardStyle(size: size)
        let overlay = CardOverlayView(style: style, captionText: "5120 × 2880")
        overlay.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height.rounded())
        overlay.layoutSubtreeIfNeeded()
        let buttons = (overlay.accessibilityChildren() as? [CardButton]) ?? []
        #expect(buttons.count == 5)
        for (i, a) in buttons.enumerated() {
            #expect(overlay.bounds.contains(a.frame), "\(a.action) inside the card")
            for b in buttons[(i + 1)...] {
                #expect(!a.hitFrame.intersects(b.hitFrame), "\(a.action) vs \(b.action) at \(size)")
            }
        }
    }
}
