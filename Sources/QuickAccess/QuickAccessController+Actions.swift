import AppKit
import ShotzCore

/// Card actions, hover keys and drag-out (SPEC §4.3, §4.4).
extension QuickAccessController: CardViewDelegate {
    /// How long a confirmation shows before a close-after-action card leaves.
    static let closeAfterFlashDelay: Duration = .milliseconds(650)

    // MARK: Actions

    func perform(_ action: CardAction, on card: CardView) {
        guard !card.isExiting else { return }
        let capture = card.capture
        switch action {
        case .copy:
            Task { await copy(card) }
        case .save:
            Task { await save(card) }
        case .annotate:
            remove(card, animation: .fade)
            delegate?.quickAccess(requestAnnotate: capture)
        case .quickLook:
            quickLook.toggle(capture.fileURL)
        case .close:
            close(card, deleteFile: false)
        case .closeAndDelete:
            close(card, deleteFile: true)
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([capture.fileURL])
        case .copyFilePath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(capture.fileURL.path(percentEncoded: false), forType: .string)
            card.flash(String(localized: "Path Copied"), symbol: "checkmark.circle.fill", success: true)
        case .closeAll:
            for other in model.order.compactMap({ cards[$0] }) { close(other, deleteFile: false) }
        }
    }

    func close(_ card: CardView, deleteFile: Bool, animation: Exit = .fade) {
        let capture = card.capture
        remove(card, animation: animation)
        delegate?.quickAccess(didClose: capture, deleteFile: deleteFile)
    }

    private func copy(_ card: CardView) async {
        do {
            try await exporter.copyToPasteboard(imageAt: card.capture.fileURL)
            card.flash(String(localized: "Copied"), symbol: "checkmark.circle.fill", success: true)
            if settings.quickAccessCloseAfterCopy { await closeAfterFlash(card) }
        } catch {
            log.error("Copy failed: \(String(describing: error), privacy: .public)")
            card.flash(String(localized: "Couldn’t Copy"), symbol: "exclamationmark.triangle.fill", success: false)
        }
    }

    private func save(_ card: CardView) async {
        let ask = settings.askDestinationWhenSaving
        // The save panel activates Shotz; hand focus back to the user's app afterwards.
        let previous = ask ? NSWorkspace.shared.frontmostApplication : nil
        defer {
            if let previous, previous != NSRunningApplication.current { previous.activate() }
        }
        do {
            guard let url = try await exporter.saveToExportFolder(
                imageAt: card.capture.fileURL, suggestedName: card.capture.displayName, askDestination: ask
            ) else { return }
            card.flash(String(localized: "Saved"), symbol: "checkmark.circle.fill", success: true)
            delegate?.quickAccess(didExport: card.capture, to: url)
            if settings.quickAccessCloseAfterSave { await closeAfterFlash(card) }
        } catch {
            log.error("Save failed: \(String(describing: error), privacy: .public)")
            card.flash(String(localized: "Couldn’t Save"), symbol: "exclamationmark.triangle.fill", success: false)
        }
    }

    private func closeAfterFlash(_ card: CardView) async {
        try? await Task.sleep(for: Self.closeAfterFlashDelay) // cancellation only shortens the wait
        guard cards[card.capture.id] === card else { return }
        close(card, deleteFile: false)
    }

    // MARK: Hover and keys

    func card(_ card: CardView, hoverChanged inside: Bool) {
        if inside { hoverBegan(card) } else if hoveredCard === card { hoverEnded(card) }
    }

    private func hoverBegan(_ card: CardView) {
        if let other = hoveredCard, other !== card { other.setHovered(false) }
        hoveredCard = card
        timers.values.forEach { $0.pause() }
        guard let panel = card.window as? StackPanel else { return }
        // Key without activating Shotz, so hover shortcuts reach the stack.
        panel.acceptsKey = true
        panel.makeKey()
        installKeyMonitor()
    }

    func hoverEnded(_ card: CardView) {
        guard hoveredCard === card else { return }
        hoveredCard = nil
        // Moving straight onto a neighbouring card keeps the panel key.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.hoveredCard == nil else { return }
            self.removeKeyMonitor()
            for panel in self.panels.values where panel.acceptsKey {
                panel.acceptsKey = false
                if panel.isKeyWindow { self.relinquishKey(panel) }
            }
            self.timers.values.forEach { $0.start() }
        }
    }

    /// Gives keyboard focus back to the app the user was in. Re-ordering the
    /// panel (it is transparent and stays at the same place) drops key status
    /// without activating anything.
    private func relinquishKey(_ panel: StackPanel) {
        guard !quickLook.isShowing else { return }
        panel.orderOut(nil)
        panel.orderFrontRegardless()
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let windowNumber = event.windowNumber
            let action = CardAction.forKey(keyCode: event.keyCode, characters: event.charactersIgnoringModifiers, modifiers: event.modifierFlags)
            let isRepeat = event.isARepeat
            let handled = MainActor.assumeIsolated { () -> Bool in
                guard let self, let card = self.hoveredCard, let action,
                      windowNumber == card.window?.windowNumber else { return false }
                if !isRepeat { self.perform(action, on: card) }
                return true
            }
            return handled ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: CardViewDelegate

    func card(_ card: CardView, perform action: CardAction) {
        perform(action, on: card)
    }

    func cardDragWriter(_ card: CardView) -> NSPasteboardWriting? {
        do {
            let url = try exporter.exportFileURLForDrag(imageAt: card.capture.fileURL, suggestedName: card.capture.displayName)
            timers[card.capture.id]?.pause()
            return DragFileWriter(fileURL: url)
        } catch {
            log.error("Drag export failed: \(String(describing: error), privacy: .public)")
            card.flash(String(localized: "Couldn’t Prepare File"), symbol: "exclamationmark.triangle.fill", success: false)
            return nil
        }
    }

    func card(_ card: CardView, isAtSwipeEdge screenPoint: NSPoint) -> Bool {
        guard let display = panels.first(where: { $0.value === card.window })?.key,
              let layout = layouts[display], let screen = screen(for: display) else { return false }
        return layout.isAtEdge(screenPoint, screenFrame: screen.frame)
    }

    func card(_ card: CardView, dragEndedWith operation: NSDragOperation, swiped: Bool) {
        if operation != [] {
            log.info("Dropped \(card.capture.displayName, privacy: .public) (operation \(operation.rawValue))")
            if settings.quickAccessRemoveAfterDrag { close(card, deleteFile: false) }
        } else if swiped {
            close(card, deleteFile: false, animation: .slideOff)
        }
        if hoveredCard == nil { timers[card.capture.id]?.start() }
    }
}
