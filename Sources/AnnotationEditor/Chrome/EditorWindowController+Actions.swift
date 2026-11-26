import AnnotationKit
import AppKit
import UniformTypeIdentifiers

/// Menu and toolbar commands. They reach this controller through the
/// responder chain (canvas → window → controller).
extension EditorWindowController: EditorCommands, NSMenuItemValidation {
    private func finishEditing() {
        if canvas.text.isEditingText { canvas.text.endEditing() }
        if store.isInteractive { store.commitInteractiveChange() }
    }

    /// The document to export: crop-tool drafts are not part of it.
    private var exportDocument: AnnotationDocument { store.document }

    // MARK: Output

    @objc func copyImage(_ sender: Any?) {
        finishEditing()
        let doc = exportDocument, name = documentTitle
        Task {
            do {
                try await exporterOut.copy(doc, name: name)
                flash(String(localized: "Copied"))
                if env.settings.editorCloseAfterCopy { window?.performClose(nil) }
            } catch { present(error) }
        }
    }

    @objc func saveImage(_ sender: Any?) {
        finishEditing()
        let doc = exportDocument, name = documentTitle
        Task {
            do {
                guard let url = try await exporterOut.save(doc, name: name) else { return }
                flash(String(localized: "Saved to \(url.deletingLastPathComponent().lastPathComponent)"))
                if env.settings.editorCloseAfterSave { window?.performClose(nil) }
            } catch { present(error) }
        }
    }

    @objc func saveImageAs(_ sender: Any?) {
        finishEditing()
        guard let window else { return }
        let doc = exportDocument, name = documentTitle
        Task {
            do {
                guard let url = try await exporterOut.saveAs(doc, name: name, window: window) else { return }
                flash(String(localized: "Saved \(url.lastPathComponent)"))
            } catch { present(error) }
        }
    }

    @objc func printImage(_ sender: Any?) {
        finishEditing()
        guard let window else { return }
        do { try exporterOut.print(exportDocument, name: documentTitle, window: window) } catch { present(error) }
    }

    @objc func openImageFile(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = true
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK else { return }
            for url in panel.urls { self?.env.openImage(url) }
        }
    }

    @objc func newFromClipboard(_ sender: Any?) { env.openClipboard() }

    func makeDragFile() -> URL? {
        finishEditing()
        do { return try exporterOut.dragFile(exportDocument, name: documentTitle) } catch {
            present(error)
            return nil
        }
    }

    // MARK: Edit

    @objc func copy(_ sender: Any?) {
        // ⌘C with nothing selected copies the flattened image (SPEC §5.5).
        guard !model.selection.isEmpty else { copyImage(sender); return }
        writeSelectionToPasteboard()
    }

    @objc func cut(_ sender: Any?) {
        guard !model.selection.isEmpty else { return }
        writeSelectionToPasteboard()
        model.deleteSelection()
    }

    @objc func paste(_ sender: Any?) {
        guard let payload = ObjectPasteboard.read(), !payload.objects.isEmpty else { return }
        let offset = ObjectPasteboard.placementOffset(for: payload.objects, in: store.document, step: model.unit * 4)
        model.insert(payload.objects, offset: offset, actionName: String(localized: "Paste"))
    }

    @objc func delete(_ sender: Any?) { model.deleteSelection() }
    @objc override func selectAll(_ sender: Any?) {
        if model.toolKind == .crop { model.setTool(.select) }
        model.selectAll()
    }
    @objc func duplicate(_ sender: Any?) { model.duplicateSelection() }

    private func writeSelectionToPasteboard() {
        do {
            try ObjectPasteboard.write(model.selectedObjects, sourcePixelSize: store.document.pixelSize)
        } catch { present(error) }
    }

    // MARK: Arrange

    @objc func bringForward(_ sender: Any?) { model.arrange(.forward) }
    @objc func sendBackward(_ sender: Any?) { model.arrange(.backward) }
    @objc func bringToFront(_ sender: Any?) { model.arrange(.front) }
    @objc func sendToBack(_ sender: Any?) { model.arrange(.back) }

    // MARK: View

    @objc func zoomIn(_ sender: Any?) { zoomStep(1) }
    @objc func zoomOut(_ sender: Any?) { zoomStep(-1) }
    @objc func zoomToFit(_ sender: Any?) { zoomFit() }
    @objc func zoomToActualSize(_ sender: Any?) { setZoom(1) }
    @objc func toggleBackgroundPanel(_ sender: Any?) { toggleBackgroundPanelVisibility() }

    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        let hasSelection = !model.selection.isEmpty
        switch item.action {
        case #selector(cut(_:)), #selector(delete(_:)), #selector(duplicate(_:)),
             #selector(bringForward(_:)), #selector(sendBackward(_:)), #selector(bringToFront(_:)), #selector(sendToBack(_:)):
            return hasSelection
        case #selector(paste(_:)):
            return ObjectPasteboard.hasObjects
        case #selector(selectAll(_:)):
            return !store.document.objects.isEmpty
        case #selector(toggleBackgroundPanel(_:)):
            item.state = backgroundPanel == nil ? .off : .on
            return true
        default:
            return true
        }
    }

    // MARK: Feedback

    /// A brief confirmation over the canvas.
    func flash(_ text: String) {
        guard let host = overlay.superview else { return }
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        host.addSubview(box)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
            box.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            box.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -24),
        ])
        box.setAccessibilityLabel(text)
        NSAccessibility.post(element: box, notification: .announcementRequested,
                             userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = 0.25
                box.animator().alphaValue = 0
            }, completionHandler: { MainActor.assumeIsolated { box.removeFromSuperview() } })
        }
    }

    func present(_ error: Error) {
        log.error("Editor command failed: \(String(describing: error), privacy: .public)")
        guard let window else { return }
        NSAlert(error: error).beginSheetModal(for: window)
    }
}
