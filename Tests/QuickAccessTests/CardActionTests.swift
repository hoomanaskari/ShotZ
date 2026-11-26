import AppKit
import Testing
@testable import QuickAccess
import ShotzCore
import ShotzUI

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
        overlay.frame = CGRect(origin: .zero, size: card)
        overlay.layoutSubtreeIfNeeded()
        return overlay
    }

    /// Edge-to-edge distance between two rectangles (negative when they overlap).
    static func gap(_ a: CGRect, _ b: CGRect) -> CGFloat {
        max(b.minX - a.maxX, a.minX - b.maxX, b.minY - a.maxY, a.minY - b.maxY)
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func visibleControlsKeepSixPointGaps(size: CardSize) {
        let frames = laidOut(size).controlFrames
        for (i, a) in frames.enumerated() {
            for b in frames[(i + 1)...] {
                let g = Self.gap(a.visible, b.visible)
                #expect(g >= CardStyle.minimumGap, "\(a.name)–\(b.name) only \(g) pt apart at \(size)")
            }
        }
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func hitTargetsAtLeast28AndNeverOverlap(size: CardSize) {
        let overlay = laidOut(size)
        let hits = overlay.controlFrames.filter { $0.name != "caption" }
        #expect(hits.count == 5)
        for (i, a) in hits.enumerated() {
            #expect(a.hit.width >= 28 && a.hit.height >= 28, "\(a.name) at \(size)")
            #expect(overlay.bounds.contains(a.hit), "\(a.name) hit area leaves the card at \(size)")
            for b in hits[(i + 1)...] {
                #expect(!a.hit.intersects(b.hit), "\(a.name) vs \(b.name) hit areas at \(size)")
            }
        }
    }

    @Test(arguments: [CardSize.small, .medium, .large])
    func nothingClipped(size: CardSize) {
        let overlay = laidOut(size)
        let inner = overlay.bounds.insetBy(dx: CardStyle.minimumGap, dy: CardStyle.minimumGap)
        for c in overlay.controlFrames {
            #expect(inner.contains(c.visible), "\(c.name) within 6 pt of the edge at \(size)")
            #expect(c.hit.width >= c.natural.width && c.hit.height >= c.natural.height, "\(c.name) squeezed at \(size)")
        }
    }

    @Test func perSizeLayouts() {
        let small = laidOut(.small), medium = laidOut(.medium), large = laidOut(.large)
        #expect(!small.pairIsLabelled && (small.button(for: .copy) as? ShotzButton)?.title == nil && (small.button(for: .copy) as? ShotzButton)?.role == .glass)
        #expect(!small.controlFrames.contains { $0.name == "caption" })
        #expect(small.button(for: .copy)?.toolTip?.contains("⌘C") == true) // icon-only still names its shortcut
        #expect(medium.pairIsLabelled && medium.controlFrames.contains { $0.name == "caption" })
        #expect((large.button(for: .save) as? ShotzButton)?.title == "Save")
    }

    @Test func glassControlsWithTooltipsWorkInANonActivatingPanel() {
        for size in [CardSize.small, .large] {
            let overlay = laidOut(size)
            for (action, button) in overlay.buttons {
                #expect(button is ShotzGlassIconButton || (button as? ShotzButton)?.role == .glass)
                #expect(button.toolTip?.contains(action.title) == true)
                #expect(button.acceptsFirstMouse(for: nil))
                #expect(!button.needsPanelToBecomeKey)
            }
        }
        let large = laidOut(.large)
        #expect(large.button(for: .copy)?.frame.width == large.button(for: .save)?.frame.width)
    }

    @Test func buttonsActivateTheirAction() {
        let overlay = laidOut(.medium)
        var fired: [CardAction] = []
        overlay.onAction = { fired.append($0) }
        for (_, button) in overlay.buttons { _ = button.accessibilityPerformPress() }
        #expect(fired == [.close, .annotate, .quickLook, .copy, .save])
    }
}
