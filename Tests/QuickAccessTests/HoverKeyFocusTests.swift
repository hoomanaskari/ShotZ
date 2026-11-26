import Foundation
import Testing
@testable import QuickAccess

@MainActor
struct HoverKeyFocusTests {
    let a = UUID(), b = UUID()
    let host = RecordingFocusHost()
    let focus: HoverKeyFocus

    init() { focus = HoverKeyFocus(host: host) }

    @Test func enteringAloneNeverTakesKey() {
        // A card appears, animates or re-lays-out under a resting pointer.
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerEntered(a))
        #expect(host.takes == 0)
        #expect(!focus.hasKey)
    }

    @Test func genuineMovementTakesKeyOnce() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        #expect(host.takes == 1)
        #expect(focus.hasKey)
    }

    @Test func buttonDownElsewhereBlocksKey() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: true))
        #expect(host.takes == 0)
        focus.handle(.pointerMoved(a, buttonsDown: false))
        #expect(host.takes == 1)
    }

    @Test func unhandledKeyReleasesAndSuppressesUntilReentry() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        focus.handle(.keyDown(isCardShortcut: true))
        #expect(host.releases == 0)
        focus.handle(.keyDown(isCardShortcut: false))
        #expect(host.releases == 1)
        #expect(!focus.hasKey)
        // Jiggling the pointer while typing must not grab key again.
        focus.handle(.pointerMoved(a, buttonsDown: false))
        #expect(host.takes == 1)
        focus.handle(.pointerExited(a))
        #expect(host.releases == 1) // nothing left to release
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        #expect(host.takes == 2)
    }

    @Test func exitReleases() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        focus.handle(.pointerExited(a))
        #expect(host.releases == 1)
        #expect(focus.hovered == nil)
    }

    @Test func movingBetweenCardsWithEnterBeforeExit() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        // AppKit may deliver B's enter before A's exit.
        focus.handle(.pointerEntered(b))
        focus.handle(.pointerExited(a)) // stale: A is no longer the hovered card
        #expect(focus.hovered == b)
        #expect(host.releases == 0)
        focus.handle(.pointerExited(b))
        #expect(host.releases == 1)
    }

    @Test(arguments: [HoverKeyFocus.Event.spaceChanged, .otherAppActivated, .dragStarted])
    func systemEventsReleaseAndSuppress(_ event: HoverKeyFocus.Event) {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        focus.handle(event)
        #expect(host.releases == 1)
        focus.handle(.pointerMoved(a, buttonsDown: false))
        #expect(host.takes == 1)
    }

    @Test func lastCardClosedReleases() {
        focus.handle(.pointerEntered(a))
        focus.handle(.pointerMoved(a, buttonsDown: false))
        focus.handle(.lastCardClosed)
        #expect(host.releases == 1)
        #expect(focus.hovered == nil)
        focus.handle(.lastCardClosed)
        #expect(host.releases == 1)
    }
}
