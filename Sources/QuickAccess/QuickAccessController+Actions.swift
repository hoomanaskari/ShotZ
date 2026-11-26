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
            // Hidden while the editor is open (SPEC §4.4): not a close, so no
            // restore-last-closed entry and no delete. The editor's close
            // presents the capture again (§4.6).
            remove(card, animation: .fade)
            delegate?.quickAccess(requestAnnotate: capture)
        case .quickLook:
            quickLook.toggle(card.source.fileURL)
        case .close:
            close(card, deleteFile: false)
        case .closeAndDelete:
            close(card, deleteFile: true)
        case .showInFinder:
            NSWorkspace.shared.activateFileViewerSelecting([card.source.fileURL])
        case .copyFilePath:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(card.source.fileURL.path(percentEncoded: false), forType: .string)
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
            try await exporter.copyToPasteboard(imageAt: card.source.fileURL)
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
                imageAt: card.source.fileURL, suggestedName: card.source.exportName, askDestination: ask
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
        if inside {
            if let other = hoveredCard, other !== card { other.setHovered(false) }
            hoveredCard = card
            timers.values.forEach { $0.pause() }
            focus.handle(.pointerEntered(card.capture.id))
        } else if hoveredCard === card {
            hoveredCard = nil
            focus.handle(.pointerExited(card.capture.id))
            timers.values.forEach { $0.start() }
        }
    }

    func cardPointerMoved(_ card: CardView, buttonsDown: Bool) {
        guard hoveredCard === card else { return }
        focus.handle(.pointerMoved(card.capture.id, buttonsDown: buttonsDown))
    }

    /// Decides what a key-down reaching the stack does. Returns true when it
    /// was a card shortcut (consumed); anything else releases key at once.
    func handleKeyDown(keyCode: UInt16, characters: String?, modifiers: NSEvent.ModifierFlags, windowNumber: Int, isRepeat: Bool) -> Bool {
        guard let card = hoveredCard, windowNumber == card.window?.windowNumber,
              let action = CardAction.forKey(keyCode: keyCode, characters: characters, modifiers: modifiers)
        else {
            focus.handle(.keyDown(isCardShortcut: false))
            return false
        }
        focus.handle(.keyDown(isCardShortcut: true))
        if !isRepeat { perform(action, on: card) }
        return true
    }

    func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let keyCode = event.keyCode, chars = event.charactersIgnoringModifiers
            let mods = event.modifierFlags, window = event.windowNumber, isRepeat = event.isARepeat
            let handled = MainActor.assumeIsolated {
                self?.handleKeyDown(keyCode: keyCode, characters: chars, modifiers: mods, windowNumber: window, isRepeat: isRepeat) ?? false
            }
            return handled ? nil : event
        }
    }

    func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    // MARK: CardViewDelegate

    func card(_ card: CardView, perform action: CardAction) {
        perform(action, on: card)
    }

    func cardDragWriter(_ card: CardView) -> NSPasteboardWriting? {
        do {
            let url = try exporter.exportFileURLForDrag(imageAt: card.source.fileURL, suggestedName: card.source.exportName)
            timers[card.capture.id]?.pause()
            focus.handle(.dragStarted)
            dragFiles[card.capture.id] = url
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
        if let file = dragFiles.removeValue(forKey: card.capture.id), operation == [] {
            DragExportJanitor.removeLater(file: file, root: dragRoot)
        }
        if operation != [] {
            log.info("Dropped \(card.capture.displayName, privacy: .public) (operation \(operation.rawValue))")
            if settings.quickAccessRemoveAfterDrag { close(card, deleteFile: false) }
        } else if swiped {
            close(card, deleteFile: false, animation: .slideOff)
        }
        if hoveredCard == nil { timers[card.capture.id]?.start() }
    }
}
