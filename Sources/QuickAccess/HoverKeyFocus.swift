import Foundation

/// What `HoverKeyFocus` drives. The live host makes the hovered card's panel
/// key (without activating Shotz) and hands focus back; tests use a recorder.
@MainActor protocol KeyFocusHost: AnyObject {
    func takeKey()
    func relinquishKey()
}

/// When the stack may hold keyboard focus (SPEC §4.3 hover shortcuts) without
/// ever eating the owner's typing by accident. Pure state machine; unit-tested.
///
/// - Key is taken only on genuine pointer movement inside a card with no mouse
///   button down — never because a card appeared, animated or re-laid-out
///   under a resting pointer.
/// - Any key that is not a card shortcut releases key at once, and key stays
///   released until the pointer leaves and comes back.
/// - Leaving the card, a Space change, another app activating, a drag starting
///   or the last card closing all release key.
@MainActor final class HoverKeyFocus {
    enum Event: Equatable {
        /// Hover began (pointer moved in, or a card arrived under it).
        case pointerEntered(UUID)
        /// A real mouse-moved event inside a card.
        case pointerMoved(UUID, buttonsDown: Bool)
        case pointerExited(UUID)
        case keyDown(isCardShortcut: Bool)
        case spaceChanged
        case otherAppActivated
        case dragStarted
        case lastCardClosed
    }

    weak var host: KeyFocusHost?
    private(set) var hovered: UUID?
    private(set) var hasKey = false
    /// Set after a release that the pointer has not yet "undone" by leaving.
    private(set) var suppressed = false

    init(host: KeyFocusHost? = nil) { self.host = host }

    func handle(_ event: Event) {
        switch event {
        case .pointerEntered(let id):
            if hovered != id { suppressed = false }
            hovered = id
        case .pointerMoved(let id, let buttonsDown):
            if hovered != id {
                // Moved onto another card without an exit in between.
                hovered = id
                suppressed = false
            }
            guard !buttonsDown, !suppressed, !hasKey else { return }
            hasKey = true
            host?.takeKey()
        case .pointerExited(let id):
            guard hovered == id else { return }
            hovered = nil
            suppressed = false
            release()
        case .keyDown(let isCardShortcut):
            guard !isCardShortcut else { return }
            suppressed = true
            release()
        case .spaceChanged, .otherAppActivated, .dragStarted:
            suppressed = true
            release()
        case .lastCardClosed:
            hovered = nil
            suppressed = false
            release()
        }
    }

    private func release() {
        guard hasKey else { return }
        hasKey = false
        host?.relinquishKey()
    }
}
