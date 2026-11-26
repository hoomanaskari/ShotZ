import AppKit
import Quartz
import ShotzCore

/// One per display that has cards (ARCHITECTURE §4): borderless, non-activating,
/// above full-screen apps, on all Spaces, invisible to screen captures.
/// It becomes key only while the pointer is over a card, so hover shortcuts
/// reach it without activating Shotz.
@MainActor final class StackPanel: NSPanel {
    /// Toggled by the controller while a card is hovered.
    var acceptsKey = false
    weak var quickLook: QuickLookPresenter?

    init(frame: CGRect, shareable: Bool) {
        super.init(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        // Never in Shotz's own (or anyone's) captures. Debug builds may opt in
        // so the stack can be screenshotted while developing.
        sharingType = shareable ? .readOnly : .none
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovable = false
        animationBehavior = .none
        becomesKeyOnlyIfNeeded = false
        isExcludedFromWindowsMenu = true
        let content = StackContainerView(frame: CGRect(origin: .zero, size: frame.size))
        contentView = content
        if StackDebugSnapshot.enabled, let name = DebugHooks.string("QuickAccessDebugAppearance") {
            appearance = NSAppearance(named: name == "light" ? .aqua : .darkAqua)
        }
        setAccessibilityRole(.group)
        setAccessibilityLabel(String(localized: "ShotZ screenshots"))
    }

    override var canBecomeKey: Bool { acceptsKey }
    override var canBecomeMain: Bool { false }

    // MARK: Quick Look (the key window's responder chain controls the panel)

    // Quick Look calls these on the main thread.
    override nonisolated func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        MainActor.assumeIsolated { quickLook != nil }
    }

    override nonisolated func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        MainActor.assumeIsolated {
            panel?.dataSource = quickLook
            panel?.delegate = quickLook
        }
    }

    override nonisolated func endPreviewPanelControl(_ panel: QLPreviewPanel!) {}
}

/// Panel content: holds cards; empty space is not a hit target.
@MainActor final class StackContainerView: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        autoresizingMask = [.width, .height]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? {
        for sub in subviews.reversed() where !sub.isHidden {
            if let hit = sub.hitTest(convert(point, from: superview)) { return hit }
        }
        return nil
    }

    var cards: [CardView] { subviews.compactMap { $0 as? CardView } }
}
