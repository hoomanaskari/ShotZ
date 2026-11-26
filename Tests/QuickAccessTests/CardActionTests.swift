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
struct CardOverlayLayoutTests {
    func laidOut(_ size: CardSize) -> CardOverlayView {
        let card = CGSize(width: size.width, height: size.height.rounded())
        let overlay = CardOverlayView(style: CardStyle(size: size), captionText: "5120 × 2880", cardSize: card)
        overlay.frame = CGRect(x: 0, y: 0, width: size.width, height: size.height.rounded())
        overlay.layoutSubtreeIfNeeded()
        return overlay
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func hitTargetsAtLeast28AndInsideTheCard(size: CardSize) {
        let overlay = laidOut(size)
        #expect(overlay.buttons.count == 5)
        for (action, button) in overlay.buttons {
            #expect(button.frame.width >= 28 && button.frame.height >= 28, "\(action) at \(size)")
            #expect(overlay.bounds.contains(button.frame), "\(action) inside the card at \(size)")
        }
    }

    /// Edge-to-edge distance between two rectangles (negative when they overlap).
    static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(b.minX - a.maxX, a.minX - b.maxX, b.minY - a.maxY, a.minY - b.maxY)
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func controlsKeepSixPointGaps(size: CardSize) {
        let overlay = laidOut(size)
        let frames = overlay.controlFrames // 28-pt hit frames, larger than the chrome
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                let g = Self.gap(a.frame, b.frame)
                #expect(g >= CardStyle.minimumGap, "\(a.name)–\(b.name) only \(g) pt apart at \(size)")
            }
        }
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func nothingClipped(size: CardSize) {
        let overlay = laidOut(size)
        for c in overlay.controlFrames {
            #expect(overlay.bounds.insetBy(dx: CardStyle.minimumGap, dy: CardStyle.minimumGap).contains(c.frame), "\(c.name) within 6 pt of the edge at \(size)")
            #expect(c.frame.width >= c.natural.width && c.frame.height >= c.natural.height, "\(c.name) squeezed at \(size)")
        }
    }

    @Test func perSizeLayouts() {
        let small = laidOut(.small), medium = laidOut(.medium), large = laidOut(.large)
        #expect(!small.pairIsLabelled && small.button(for: .copy)?.title == nil)
        #expect(!small.controlFrames.contains { $0.name == "caption" })
        #expect(small.button(for: .copy)?.toolTip?.contains("⌘C") == true) // icon-only still names its shortcut
        #expect(medium.pairIsLabelled && medium.controlFrames.contains { $0.name == "caption" })
        #expect(large.pairIsLabelled && large.button(for: .save)?.title == "Save")
    }

    @Test func copySaveAreEqualWidthGlassWithTooltips() {
        let overlay = laidOut(.large)
        let copy = overlay.button(for: .copy), save = overlay.button(for: .save)
        #expect(copy?.frame.width == save?.frame.width)
        for (action, button) in overlay.buttons {
            #expect(button.role == .glass)
            #expect(button.toolTip?.contains(action.title) == true)
            #expect(button.acceptsFirstMouse(for: nil)) // works in the non-activating panel
            #expect(!button.needsPanelToBecomeKey)
        }
        #expect(overlay.button(for: .copy)?.toolTip?.contains("⌘C") == true)
    }

    @Test func buttonsActivateTheirAction() {
        let overlay = laidOut(.medium)
        var fired: [CardAction] = []
        overlay.onAction = { fired.append($0) }
        for (_, button) in overlay.buttons { _ = button.accessibilityPerformPress() }
        #expect(fired == [.close, .annotate, .quickLook, .copy, .save])
    }
}
