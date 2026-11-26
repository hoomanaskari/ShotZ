import AnnotationKit
import AppKit

/// Wiring between the model, the store's change stream, the canvas and the chrome.
extension EditorWindowController {
    func bind() {
        canvas.keyHandler = self
        keyHandler.onToggleBackground = { [weak self] in self?.toggleBackgroundPanelVisibility() }
        canvas.onLayoutChange = { [weak self] in self?.layoutChanged() }
        canvas.onInteractionEnded = { [weak self] in self?.interactionEnded() }
        optionsBar.onFocusCanvas = { [weak self] in self?.focusCanvas() }
        (window as? EditorWindow)?.onCancel = { [weak self] in self?.focusCanvas() }

        toolbarController.onSelectTool = { [weak self] kind in
            self?.model.setTool(kind)
            self?.focusCanvas()
        }
        toolbarController.onToggleBackground = { [weak self] in self?.toggleBackgroundPanelVisibility() }
        toolbarController.onCopy = { [weak self] in self?.copyImage(nil) }
        toolbarController.onSave = { [weak self] in self?.saveImage(nil) }
        toolbarController.dragHandle.makeFile = { [weak self] in self?.makeDragFile() }

        optionsBar.onCropApply = { [weak self] in (self?.model.tool as? CropTool)?.apply() }
        optionsBar.onCropCancel = { [weak self] in self?.model.setTool(.select) }
        optionsBar.onCropAspect = { [weak self] in (self?.model.tool as? CropTool)?.applyAspect() }
        optionsBar.onCropSize = { [weak self] w, h in (self?.model.tool as? CropTool)?.setSize(width: w, height: h) }

        model.observe { [weak self] event in
            guard let self else { return }
            switch event {
            case .tool:
                self.canvas.relayout()
                self.canvas.updateCursor()
                self.refreshOverlay()
            case .selection, .overlay:
                self.canvas.layers.setHidden(self.model.hiddenObjectIDs)
                self.refreshOverlay()
            case .toolSettings:
                break
            }
        }

        let clip = scrollView.contentView
        clip.postsBoundsChangedNotifications = true
        let center = NotificationCenter.default
        center.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportChanged() }
        }
        center.addObserver(forName: NSView.frameDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.viewportChanged() }
        }
        center.addObserver(forName: NSScrollView.didEndLiveMagnifyNotification, object: scrollView, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.rasterizeForZoom() }
        }
        center.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isTerminating = true
                self?.persistNow()
            }
        }
        scrollView.onZoomSettled = { [weak self] in self?.rasterizeForZoom() }

        scheduleThumbnail(delay: 0)
        let stream = store.changes
        changeTask = Task { [weak self] in
            for await change in stream {
                guard let self else { return }
                self.apply(change)
            }
        }
    }

    func focusCanvas() {
        guard let window, !canvas.text.isEditingText else { return }
        window.makeFirstResponder(canvas)
    }

    /// Redraws only what changed (ARCHITECTURE §6).
    func apply(_ change: DocumentChange) {
        let start = ContinuousClock.now
        let doc = store.document
        if change.documentPropertiesChanged {
            canvas.relayout()
            canvas.layers.sync(doc, rerenderRedactions: true)
            backgroundPanel?.scheduleRebuild()
        } else if change.reordered {
            canvas.layers.sync(doc, interactive: store.isInteractive)
        } else {
            canvas.layers.sync(doc, changed: change.objectIDs, interactive: store.isInteractive)
        }
        perf?.recordUpdate(ContinuousClock.now - start, reason: change.reason)
        model.pruneSelection()
        refreshOverlay()
        scheduleThumbnail()
        switch change.reason {
        case .undo, .redo:
            optionsBar.scheduleRebuild()
            backgroundPanel?.scheduleRebuild()
        default:
            break
        }
        schedulePersist()
    }

    /// A mouse gesture finished: a drag commits without a change event, so
    /// finalise preview-quality layers and schedule the save here.
    func interactionEnded() {
        guard !store.isInteractive else { return }
        let start = ContinuousClock.now
        canvas.layers.finishInteraction(store.document)
        perf?.recordFinish(ContinuousClock.now - start)
        schedulePersist()
    }

    /// The drag handle's preview of the result, rendered off the main thread after edits settle.
    func scheduleThumbnail(delay: Double = 0.35) {
        thumbnailWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            let document = self.store.document
            let base = self.base
            Task { [weak self] in
                let image = await Task.detached(priority: .utility) { () -> CGImage? in
                    let side = max(document.imageRect.width, document.imageRect.height, 1)
                    return try? AnnotationRenderer.renderImage(document, base: base, outputScale: 120 / side) // a failed preview just stays empty
                }.value
                guard let image else { return }
                self?.toolbarController.dragHandle.thumbnail = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        thumbnailWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    // MARK: Overlay

    func viewportChanged() {
        recenterIfNeeded()
        model.pointsPerPixel = scrollView.magnification
        canvas.text.zoomChanged(pointsPerPixel: scrollView.magnification)
        refreshOverlay()
        updateZoomTitle()
    }

    /// The canvas extent changed (crop, background, crop tool): refit when the
    /// view was showing the whole canvas, otherwise keep the zoom and re-centre.
    func layoutChanged() {
        if wasFitted { zoomFit() } else { recenterIfNeeded() }
        refreshOverlay()
    }

    /// Keeps a document smaller than the viewport centred.
    func recenterIfNeeded() {
        guard !isRecentering else { return }
        let clip = scrollView.contentView
        let constrained = clip.constrainBoundsRect(clip.bounds)
        guard abs(constrained.minX - clip.bounds.minX) > 0.5 || abs(constrained.minY - clip.bounds.minY) > 0.5 else { return }
        isRecentering = true
        defer { isRecentering = false }
        clip.setBoundsOrigin(constrained.origin)
        scrollView.reflectScrolledClipView(clip)
    }

    /// Image-pixel point → overlay point.
    func overlayPoint(_ p: CGPoint) -> CGPoint {
        canvas.convert(canvas.canvasLayout.toCanvas(p), to: overlay)
    }

    func overlayRect(_ r: CGRect) -> CGRect {
        let a = overlayPoint(CGPoint(x: r.minX, y: r.minY)), b = overlayPoint(CGPoint(x: r.maxX, y: r.maxY))
        return CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(b.x - a.x), height: abs(b.y - a.y))
    }

    func refreshOverlay() {
        var content = OverlayView.Content()
        let several = model.selection.count > 1
        for object in model.selectedObjects where !model.hiddenObjectIDs.contains(object.id) {
            switch object.shape {
            case .line where !several, .arrow where !several:
                break
            case .counter(let c):
                let r = object.style.fontSize
                let circle = CGRect(x: c.center.x - r, y: c.center.y - r, width: 2 * r, height: 2 * r)
                content.selectionOutlines.append(CGPath(ellipseIn: overlayRect(circle).insetBy(dx: -3, dy: -3), transform: nil))
            default:
                content.selectionOutlines.append(CGPath(rect: overlayRect(model.frame(of: object)).insetBy(dx: -0.5, dy: -0.5), transform: nil))
            }
            for h in model.handles(for: object) {
                content.handles.append((Handle(kind: h.kind, position: overlayPoint(h.position)), h.kind == .control || h.kind == .tail))
            }
        }
        if let id = model.editingCounterID, let object = model.document[id: id] {
            // The counter whose number is being typed.
            content.hintOutlines.append(CGPath(ellipseIn: overlayRect(model.frame(of: object)).insetBy(dx: -6, dy: -6), transform: nil))
        }
        for id in model.redactionHintIDs {
            guard let object = model.document[id: id] else { continue }
            content.hintOutlines.append(CGPath(rect: overlayRect(model.frame(of: object)).insetBy(dx: -0.5, dy: -0.5), transform: nil))
        }
        for g in model.guides {
            switch g.axis {
            case .vertical:
                content.guides.append((overlayPoint(CGPoint(x: g.position, y: g.start)), overlayPoint(CGPoint(x: g.position, y: g.end))))
            case .horizontal:
                content.guides.append((overlayPoint(CGPoint(x: g.start, y: g.position)), overlayPoint(CGPoint(x: g.end, y: g.position))))
            }
        }
        content.marquee = model.marquee.map(overlayRect)
        if model.toolKind == .crop, let draft = model.cropDraft {
            content.crop = (overlayRect(draft), overlayRect(model.imageBounds))
            content.cropLabel = "\(Int(draft.width)) × \(Int(draft.height))"
        }
        overlay.show(content)
    }

    // MARK: Persistence

    /// Writes the editable document back silently (SPEC §5.1, decision 2).
    func schedulePersist() {
        guard documentURL != nil else { return }
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            // Never save half a drag; try again once it ends.
            if self.store.isInteractive { self.schedulePersist() } else { self.persistNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
    }

    func persistNow() {
        saveWork?.cancel()
        guard let url = documentURL, store.document != lastSavedDocument else { return }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try store.document.save(to: url)
            lastSavedDocument = store.document
        } catch {
            log.error("Cannot save editor document: \(error.localizedDescription, privacy: .public)")
        }
    }
}

extension EditorWindowController: CanvasKeyHandling {
    func canvasKeyDown(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection([.command, .control, .option])
        guard mods.isEmpty else { return false }
        let shift = event.modifierFlags.contains(.shift)
        let key: EditorKeyHandler.Key
        switch event.keyCode {
        case 53: key = .escape
        case 36, 76: key = .returnKey
        case 51, 117: key = .delete
        case 123: key = .arrow(dx: -1, dy: 0)
        case 124: key = .arrow(dx: 1, dy: 0)
        case 125: key = .arrow(dx: 0, dy: 1)
        case 126: key = .arrow(dx: 0, dy: -1)
        default:
            guard let c = event.charactersIgnoringModifiers?.first else { return false }
            key = .character(c)
        }
        return keyHandler.handle(key, shift: shift)
    }
}

extension EditorWindowController: EditorUndoTarget {
    func undoDocument() {
        if canvas.text.isEditingText { canvas.text.endEditing() }
        model.endCounterValueEditing(commit: true)
        store.undo()
    }

    func redoDocument() {
        if canvas.text.isEditingText { canvas.text.endEditing() }
        model.endCounterValueEditing(commit: true)
        store.redo()
    }

    var canUndoDocument: Bool { store.canUndo }
    var canRedoDocument: Bool { store.canRedo }
    var undoTitle: String { store.undoActionName.map { String(localized: "Undo \($0)") } ?? String(localized: "Undo") }
    var redoTitle: String { store.redoActionName.map { String(localized: "Redo \($0)") } ?? String(localized: "Redo") }
}
