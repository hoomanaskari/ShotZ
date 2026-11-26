import os
import AppKit
import Combine
import ShotzCore

/// The quick-access stack (SPEC §4, ARCHITECTURE §4).
///
/// Holds the card order (`StackModel`), one `StackPanel` per display that has
/// cards, and the card views. Geometry comes from `StackLayout`; motion from
/// `CardAnimator`. Actions are in `QuickAccessController+Actions.swift`.
@MainActor public final class QuickAccessController: QuickAccessPresenting {
    public weak var delegate: QuickAccessDelegate?

    let settings: SettingsStore
    let exporter: ExportService
    let log = ShotzLog.logger("QuickAccess")
    let quickLook = QuickLookPresenter()

    var model = StackModel<UUID>()
    var cards: [UUID: CardView] = [:]
    var panels: [CGDirectDisplayID: StackPanel] = [:]
    var layouts: [CGDirectDisplayID: StackLayout] = [:]
    var timers: [UUID: AutoCloseTimer] = [:]
    var hoveredCard: CardView?
    var keyMonitor: Any?
    var focusOwnerBeforeHover: NSRunningApplication?
    private(set) var applied: AppliedSettings
    /// Decides when the stack holds keyboard focus (see `HoverKeyFocus`).
    let focus = HoverKeyFocus()
    /// Where `ExportService` puts per-drag copies; swept on launch.
    let dragRoot = ShotzPaths.default.dragExports
    /// The export copy of each card's drag in flight.
    var dragFiles: [UUID: URL] = [:]
    private var selfTest: StackSelfTest?
    private var observers: [NSObjectProtocol] = []
    private var settingsSink: AnyCancellable?
    private var debugSnapshot: StackDebugSnapshot?

    /// Settings that change the stack's shape, compared on every settings change.
    struct AppliedSettings: Equatable {
        var size: CardSize, side: StackSide, display: StackDisplay, autoClose: Int
    }

    /// `-QuickAccessDebug YES` (debug only): lets screenshots include the stack
    /// and enables `StackDebugSnapshot`.
    private let shareable = StackDebugSnapshot.enabled

    public init(settings: SettingsStore, exporter: ExportService) {
        self.settings = settings
        self.exporter = exporter
        applied = AppliedSettings(
            size: settings.quickAccessSize, side: settings.quickAccessSide,
            display: settings.quickAccessDisplay, autoClose: settings.quickAccessAutoCloseSeconds
        )
        observe()
        focus.host = self
        let root = dragRoot
        Task.detached(priority: .utility) { DragExportJanitor.purge(root: root) }
        debugSnapshot = StackDebugSnapshot(panels: { [weak self] in self?.panels ?? [:] }) { [log] in
            log.info("\($0, privacy: .private)")
        }
    }

    // MARK: QuickAccessPresenting

    public func present(_ capture: CaptureResult) {
        present(capture, imageURL: nil)
    }

    /// Shows `capture` as the newest card. `imageURL` is the flattened
    /// annotated image a card returning from the editor shows and delivers
    /// (SPEC §4.6). A capture already in the stack is replaced, never duplicated.
    public func present(_ capture: CaptureResult, imageURL: URL?) {
        let start = CACurrentMediaTime()
        if let existing = cards[capture.id] {
            if hoveredCard === existing { card(existing, hoverChanged: false) }
            discard(existing, animation: .none)
        }

        let card = CardView(source: CardSource(capture: capture, imageURL: imageURL), size: applied.size)
        card.delegate = self
        cards[capture.id] = card
        let evicted = model.insert(capture.id, limit: StackLayout.maxVisible) { self.group(of: $0) }

        let display = group(of: capture.id)
        let panel = panel(for: display)
        guard let container = panel.contentView else { return }
        container.addSubview(card)
        layoutAll(animated: true, entering: capture.id)
        panel.orderFrontRegardless()

        for id in evicted {
            guard let old = cards[id] else { continue }
            remove(old, animation: .fade)
            delegate?.quickAccess(didClose: old.capture, deleteFile: false)
        }
        startAutoClose(for: card)
        loadThumbnail(for: card, start: start)
        FrameProbe.measure(in: card) { [log] in
            log.info("Card first frame \(Int((CACurrentMediaTime() - start) * 1000)) ms after present")
        }
        log.info("Present \(capture.displayName, privacy: .private) on display \(display)")
        if selfTest == nil, let test = StackSelfTest.makeIfRequested(controller: self) {
            selfTest = test
            CardView.ignoresRealPointer = true
            test.start()
        }
    }

    public func dismiss(id: CaptureResult.ID) {
        guard let card = cards[id] else { return }
        remove(card, animation: .fade)
    }

    public func dismissAll() {
        for card in Array(cards.values) { remove(card, animation: .none) }
    }

    // MARK: Groups and panels

    /// The display whose stack shows `id`.
    func group(of id: UUID) -> CGDirectDisplayID {
        let captured = cards[id]?.capture.displayID ?? CGMainDisplayID()
        return DisplayChoice.resolve(
            captured: captured, setting: applied.display,
            available: NSScreen.screens.compactMap(\.displayID), main: CGMainDisplayID()
        )
    }

    func screen(for display: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == display } ?? NSScreen.screens.first
    }

    private func panel(for display: CGDirectDisplayID) -> StackPanel {
        if let panel = panels[display] { return panel }
        let frame = layout(for: display)?.panelFrame ?? .zero
        let panel = StackPanel(frame: frame, shareable: shareable)
        panel.quickLook = quickLook
        panels[display] = panel
        return panel
    }

    private func layout(for display: CGDirectDisplayID) -> StackLayout? {
        guard let screen = screen(for: display) else { return nil }
        return StackLayout(
            visibleFrame: screen.visibleFrame, side: applied.side,
            cardSize: CGSize(width: applied.size.width, height: applied.size.height)
        )
    }

    // MARK: Layout

    /// Places every card in its display's stack. Cards that changed slot
    /// spring there; `entering` slides in from the edge.
    func layoutAll(animated: Bool, entering: UUID? = nil) {
        let groups = model.grouped { self.group(of: $0) }
        for (key, ids) in groups {
            guard let display = key.base as? CGDirectDisplayID, let layout = layout(for: display) else { continue }
            let panel = panel(for: display)
            let geometryChanged = layouts[display] != layout
            if panel.frame != layout.panelFrame {
                panel.setFrame(layout.panelFrame, display: false)
            }
            layouts[display] = layout
            guard let container = panel.contentView else { continue }
            for (id, slot) in zip(ids, layout.slots(count: ids.count)) {
                guard let card = cards[id] else { continue }
                if card.superview !== container {
                    card.removeFromSuperview()
                    container.addSubview(card)
                }
                guard let slot else {
                    card.isHidden = true
                    continue
                }
                let target = layout.cardFrame(slot: slot)
                if id == entering {
                    CardAnimator.move(card, to: target, from: layout.entranceFrame(slot: slot), animated: true)
                    CardAnimator.fadeIn(card)
                } else if card.isHidden {
                    card.isHidden = false
                    CardAnimator.move(card, to: target, animated: false)
                    CardAnimator.fadeIn(card)
                } else {
                    CardAnimator.move(card, to: target, animated: animated && !geometryChanged)
                }
            }
            if !panel.isVisible { panel.orderFrontRegardless() }
        }
        hideEmptyPanels()
        // A card may have slid under (or away from) a resting pointer.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.cards.values.forEach { $0.refreshHover() }
        }
    }

    private func hideEmptyPanels() {
        for (display, panel) in panels {
            let live = (panel.contentView as? StackContainerView)?.cards ?? []
            if live.isEmpty {
                panel.orderOut(nil)
                panels[display] = nil
                layouts[display] = nil
            }
        }
    }

    // MARK: Removal

    enum Exit { case none, fade, slideOff }

    /// Takes a card out of the stack and animates it away. No delegate call.
    func remove(_ card: CardView, animation: Exit) {
        guard !card.isExiting, cards[card.capture.id] === card else { return }
        let id = card.capture.id
        if hoveredCard === card { self.card(card, hoverChanged: false) }
        card.markExiting()
        model.remove(id)
        cards[id] = nil
        timers.removeValue(forKey: id)?.cancel()
        quickLook.closeIfShowing(card.source.fileURL)
        let display = panels.first { $0.value === card.window }?.key
        switch animation {
        case .none:
            discard(card, animation: .none)
        case .fade:
            CardAnimator.exit(card) { [weak self] in self?.discard(card, animation: .none) }
        case .slideOff:
            let layout = display.flatMap { layouts[$0] } ?? layouts.values.first
            let target = layout?.offEdge(card.frame) ?? card.frame.offsetBy(dx: -card.frame.maxX, dy: 0)
            CardAnimator.slideOut(card, to: target) { [weak self] in self?.discard(card, animation: .none) }
        }
        layoutAll(animated: true)
        if cards.isEmpty { focus.handle(.lastCardClosed) }
    }

    /// Drops the view immediately.
    private func discard(_ card: CardView, animation: Exit) {
        if cards[card.capture.id] === card {
            cards[card.capture.id] = nil
            model.remove(card.capture.id)
            timers.removeValue(forKey: card.capture.id)?.cancel()
        }
        card.removeFromSuperview()
        hideEmptyPanels()
    }

    // MARK: Thumbnails and timers

    private func loadThumbnail(for card: CardView, start: CFTimeInterval?) {
        let scale = card.window?.backingScaleFactor ?? 2
        let maxPixels = ThumbnailLoader.maxPixelSize(pixelSize: card.source.pixelSize, cardSize: card.bounds.size, scale: scale)
        let url = card.source.fileURL
        Task { [weak card, log] in
            guard let image = await ThumbnailLoader.load(url: url, maxPixelSize: maxPixels) else {
                log.error("No thumbnail for \(url.lastPathComponent, privacy: .private)")
                return
            }
            guard let card else { return }
            card.setThumbnail(image, animated: true)
            if let start {
                FrameProbe.measure(in: card) {
                    log.info("Thumbnail on screen \(Int((CACurrentMediaTime() - start) * 1000)) ms after present (\(image.width)×\(image.height) px)")
                }
            }
            let cardSize = card.bounds.size
            if ThumbnailLoader.coverage(pixelSize: card.source.pixelSize, cardSize: cardSize) < ThumbnailLoader.backdropThreshold,
               let backdrop = await ThumbnailLoader.backdrop(from: image, cardSize: cardSize) {
                card.setBackdrop(backdrop)
            }
        }
    }

    private func startAutoClose(for card: CardView) {
        timers.removeValue(forKey: card.capture.id)?.cancel()
        guard applied.autoClose > 0 else { return }
        let timer = AutoCloseTimer(seconds: TimeInterval(applied.autoClose)) { [weak self, weak card] in
            guard let self, let card else { return }
            self.remove(card, animation: .fade)
            self.delegate?.quickAccess(didClose: card.capture, deleteFile: false)
        }
        timers[card.capture.id] = timer
        if hoveredCard == nil { timer.start() }
    }

    // MARK: Observation

    private func observe() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.screensChanged() }
        })
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.activeSpaceDidChangeNotification, NSWorkspace.didWakeNotification] {
            observers.append(workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.focus.handle(.spaceChanged)
                    self?.screensChanged()
                }
            })
        }
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            let activated = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.processIdentifier
            MainActor.assumeIsolated {
                guard activated != NSRunningApplication.current.processIdentifier else { return }
                self?.focus.handle(.otherAppActivated)
            }
        })
        settingsSink = settings.objectWillChange.sink { [weak self] _ in
            // objectWillChange fires before the write lands; read on the next turn.
            DispatchQueue.main.async { self?.settingsChanged() }
        }
    }

    private func screensChanged() {
        log.info("Screens or Space changed; re-laying out \(self.model.count) cards")
        layoutAll(animated: false)
        for panel in panels.values { panel.orderFrontRegardless() }
    }

    private func settingsChanged() {
        let now = AppliedSettings(
            size: settings.quickAccessSize, side: settings.quickAccessSide,
            display: settings.quickAccessDisplay, autoClose: settings.quickAccessAutoCloseSeconds
        )
        apply(now)
    }

    /// Applies stack-shaping settings (also used by the self-test, which must
    /// not write to the shared preferences).
    func apply(_ now: AppliedSettings) {
        guard now != applied else { return }
        let old = applied
        applied = now
        if now.size != old.size { rebuildCards() }
        if now.autoClose != old.autoClose {
            for card in cards.values { startAutoClose(for: card) }
        }
        layoutAll(animated: false)
    }

    /// New card size: rebuild the views (metrics differ per size), keep order.
    private func rebuildCards() {
        for (id, old) in cards {
            if hoveredCard === old { card(old, hoverChanged: false) }
            let card = CardView(source: old.source, size: applied.size)
            card.delegate = self
            old.superview?.addSubview(card)
            old.removeFromSuperview()
            cards[id] = card
            loadThumbnail(for: card, start: nil)
        }
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }
}
