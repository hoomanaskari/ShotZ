import AppKit

/// Zoom (SPEC §5.1): pinch, ⌘-scroll, ⌘+ / ⌘−, ⌘0 fit, ⌘1 100 %. Range 10–800 %.
/// 100 % shows one image point per screen point (pixel-for-pixel for Retina captures).
extension EditorWindowController {
    static let zoomSteps: [CGFloat] = [0.1, 0.25, 1.0 / 3, 0.5, 2.0 / 3, 0.75, 1, 1.25, 1.5, 2, 3, 4, 6, 8]

    /// Zoom as a fraction (1 = 100 %).
    var zoom: CGFloat { scrollView.magnification * store.document.scale }

    func setZoom(_ z: CGFloat, centeredAt point: NSPoint? = nil) {
        let clamped = min(max(z, 0.1), 8)
        let m = clamped / max(store.document.scale, 0.0001)
        let center = point ?? NSPoint(x: scrollView.contentView.bounds.midX, y: scrollView.contentView.bounds.midY)
        scrollView.setMagnification(m, centeredAt: center)
        rasterizeForZoom()
    }

    /// Fit the whole canvas, never above 100 %.
    var fitZoom: CGFloat {
        let clip = scrollView.contentView.frame.size
        let extent = canvas.canvasLayout.extent
        guard extent.width > 0, extent.height > 0 else { return 1 }
        // At least 24 pt of canvas around the image on every side.
        let margin = 2 * EditorWindowController.canvasMargin
        let m = min((clip.width - margin) / extent.width, (clip.height - margin) / extent.height)
        return min(m * store.document.scale, 1)
    }

    /// True while the zoom equals "fit" (so layout changes refit).
    var wasFitted: Bool { abs(zoom - lastFitZoom) < 0.001 }

    func zoomFit() {
        let z = fitZoom
        setZoom(z)
        lastFitZoom = zoom
        // Centre the document.
        let doc = canvas.frame
        scrollView.contentView.scroll(to: NSPoint(x: doc.midX - scrollView.contentView.bounds.width / 2,
                                                  y: doc.midY - scrollView.contentView.bounds.height / 2))
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    func zoomStep(_ direction: Int) {
        let z = zoom
        let next = direction > 0
            ? Self.zoomSteps.first { $0 > z * 1.001 } ?? 8
            : Self.zoomSteps.last { $0 < z * 0.999 } ?? 0.1
        setZoom(next)
    }

    /// Re-rasterises object layers for the settled zoom (crisp at any zoom).
    func rasterizeForZoom() {
        let backing = window?.backingScaleFactor ?? 2
        canvas.layers.setRasterScale(scrollView.magnification * backing, document: store.document)
        viewportChanged()
    }

    // MARK: Zoom menu

    func setUpZoomMenu() {
        let menu = zoomMenu
        menu.removeAllItems()
        let fit = NSMenuItem(title: String(localized: "Zoom to Fit"), action: #selector(EditorCommands.zoomToFit(_:)), keyEquivalent: "0")
        menu.addItem(fit)
        let actual = NSMenuItem(title: String(localized: "Actual Size"), action: #selector(EditorCommands.zoomToActualSize(_:)), keyEquivalent: "1")
        menu.addItem(actual)
        menu.addItem(.separator())
        for z in [0.25, 0.5, 1, 2, 4, 8] as [CGFloat] {
            let item = NSMenuItem(title: "\(Int(z * 100)) %", action: #selector(zoomPreset(_:)), keyEquivalent: "")
            item.representedObject = z
            item.target = self
            menu.addItem(item)
        }
    }

    @objc func zoomPreset(_ sender: NSMenuItem) {
        guard let z = sender.representedObject as? CGFloat else { return }
        setZoom(z)
    }

    func updateZoomTitle() {
        toolbarController.actionBar?.setZoomTitle("\(Int((zoom * 100).rounded())) %")
    }
}
