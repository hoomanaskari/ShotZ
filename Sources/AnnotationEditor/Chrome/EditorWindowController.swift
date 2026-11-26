import os
import AnnotationKit
import AppKit
import ShotzCore

/// Everything an editor window needs from its coordinator.
@MainActor struct EditorEnvironment {
    let settings: SettingsStore
    let exporter: ExportService
    let library: ToolSettingsLibrary
    let backgroundPresets: BackgroundPresets
    /// Open an image file / clipboard image in a new editor.
    let openImage: (URL) -> Void
    let openClipboard: () -> Void
    /// History's export path for a capture, read and written by Save (nil for images opened from files).
    var exportRecord: ExportRecord? = nil
}

/// One editor window per capture (SPEC §5.1, ARCHITECTURE §6).
@MainActor final class EditorWindowController: NSWindowController, NSWindowDelegate {
    let store: DocumentStore
    let model: EditorModel
    let env: EditorEnvironment
    let base: BaseImageProvider
    let documentTitle: String
    /// Where the editable document is persisted (nil for images opened from files).
    let documentURL: URL?
    /// What the coordinator needs when the window closes (SPEC §4.6).
    struct CloseInfo {
        let document: AnnotationDocument
        let base: BaseImageProvider
        /// The display the window was on (CGDirectDisplayID).
        let displayID: UInt32?
        /// The app is quitting: save only, no hand-back.
        let isTerminating: Bool
    }

    var onClose: ((CloseInfo) -> Void)?
    var isTerminating = false

    let canvas: CanvasView
    let scrollView = CanvasScrollView(frame: .zero)
    let overlay = OverlayView(frame: .zero)
    let optionsBar: OptionsBarView
    let toolbarController: EditorToolbar
    let keyHandler: EditorKeyHandler
    let exporterOut: EditorExporter
    let commandMenu = EditorMenu.build()
    let zoomMenu = NSPopUpButton(frame: .zero, pullsDown: true)
    private(set) var backgroundPanel: BackgroundPanelView?
    let mainSplit = NSStackView()
    var changeTask: Task<Void, Never>?
    var saveWork: DispatchWorkItem?
    var lastSavedDocument: AnnotationDocument?
    var perf: PerfProbe?
    var lastFitZoom: CGFloat = -1
    var isRecentering = false
    let log = ShotzLog.logger("AnnotationEditor")

    init(store: DocumentStore, image: CGImage, base: BaseImageProvider, title: String, documentURL: URL?, env: EditorEnvironment) {
        self.store = store
        self.base = base
        self.env = env
        documentTitle = title
        self.documentURL = documentURL
        lastSavedDocument = store.document
        model = EditorModel(store: store, library: env.library, initialTool: env.library.lastTool)
        canvas = CanvasView(model: model, base: base, image: image)
        optionsBar = OptionsBarView(model: model)
        toolbarController = EditorToolbar(model: model, commandMenu: commandMenu)
        keyHandler = EditorKeyHandler(model: model)
        exporterOut = EditorExporter(exporter: env.exporter, settings: env.settings, base: base, record: env.exportRecord)

        let window = EditorWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialContentSize(for: canvas.canvasLayout.extent, scale: store.document.scale)),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        super.init(window: window)
        let settings = env.settings
        model.snappingSetting = { settings.editorSnapping }
        model.returnToSelectSetting = { settings.editorReturnToSelect }
        model.textHost = canvas.text
        setUpWindow(window)
        setUpContent(window)
        bind()
        if ProcessInfo.processInfo.environment["SHOTZ_EDITOR_PERF"] == "1" { perf = PerfProbe(view: canvas, log: log) }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Fits the image at ≤ 100 % within 80 % of the screen; minimum 720 × 480.
    static func initialContentSize(for extent: CGSize, scale: CGFloat) -> NSSize {
        let screen = NSScreen.main?.visibleFrame.size ?? NSSize(width: 1440, height: 900)
        let chrome = NSSize(width: 48, height: 36 + 48)
        let points = NSSize(width: extent.width / max(scale, 1), height: extent.height / max(scale, 1))
        let fit = min(1, (screen.width * 0.8 - chrome.width) / max(points.width, 1), (screen.height * 0.8 - chrome.height - 80) / max(points.height, 1))
        return NSSize(width: max(720, points.width * fit + chrome.width), height: max(480, points.height * fit + chrome.height))
    }

    private func setUpWindow(_ window: EditorWindow) {
        window.title = documentTitle
        window.representedURL = store.document.baseImageURL
        window.minSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .expanded
        window.toolbar = toolbarController.toolbar
        window.commandMenu = commandMenu
        window.undoTarget = self
        window.autorecalculatesKeyViewLoop = true
        window.delegate = self
        window.tabbingMode = .disallowed
        window.setFrameAutosaveName("")
        window.center()
        window.setAccessibilityLabel(String(localized: "Annotation editor"))
    }

    private func setUpContent(_ window: NSWindow) {
        let content = NSView()
        content.wantsLayer = true

        scrollView.documentView = canvas
        scrollView.backgroundColor = Self.backdrop
        scrollView.drawsBackground = true
        scrollView.minMagnification = 0.1 / max(store.document.scale, 0.0001)
        scrollView.maxMagnification = 8 / max(store.document.scale, 0.0001)
        scrollView.setAccessibilityLabel(String(localized: "Canvas"))

        let canvasArea = NSView()
        for v in [scrollView, overlay] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
            canvasArea.addSubview(v)
            NSLayoutConstraint.activate([
                v.leadingAnchor.constraint(equalTo: canvasArea.leadingAnchor), v.trailingAnchor.constraint(equalTo: canvasArea.trailingAnchor),
                v.topAnchor.constraint(equalTo: canvasArea.topAnchor), v.bottomAnchor.constraint(equalTo: canvasArea.bottomAnchor),
            ])
        }
        mainSplit.orientation = .horizontal
        mainSplit.spacing = 0
        mainSplit.distribution = .fill
        mainSplit.addArrangedSubview(canvasArea)
        canvasArea.setContentHuggingPriority(.init(1), for: .horizontal)

        mainSplit.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(mainSplit)
        NSLayoutConstraint.activate([
            mainSplit.leadingAnchor.constraint(equalTo: content.leadingAnchor), mainSplit.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            mainSplit.topAnchor.constraint(equalTo: content.topAnchor), mainSplit.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        setUpZoomMenu()
        optionsBar.trailingView = zoomMenu
        // The options bar sits under the toolbar as part of the window's title bar.
        optionsBar.frame = NSRect(x: 0, y: 0, width: 720, height: 36)
        let accessory = NSTitlebarAccessoryViewController()
        accessory.view = optionsBar
        accessory.layoutAttribute = .bottom
        window.addTitlebarAccessoryViewController(accessory)
        window.contentView = content
        window.initialFirstResponder = canvas
    }

    /// Neutral canvas backdrop, light/dark aware (no checkerboard).
    static let backdrop = NSColor(name: "ShotzEditorBackdrop") { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(white: 0.12, alpha: 1) : NSColor(white: 0.90, alpha: 1)
    }

    // MARK: Background panel

    func toggleBackgroundPanelVisibility() {
        if let panel = backgroundPanel {
            panel.removeFromSuperview()
            backgroundPanel = nil
        } else {
            let panel = BackgroundPanelView(model: model, presets: env.backgroundPresets)
            mainSplit.addArrangedSubview(panel)
            backgroundPanel = panel
        }
        toolbarController.setBackgroundPanelVisible(backgroundPanel != nil)
        window?.makeFirstResponder(canvas)
    }

    // MARK: Window delegate

    func windowWillClose(_ notification: Notification) {
        if canvas.text.isEditingText { canvas.text.endEditing() }
        if store.isInteractive { store.commitInteractiveChange() }
        persistNow()
        changeTask?.cancel()
        let screen = window?.screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        onClose?(CloseInfo(document: store.document, base: base, displayID: screen?.uint32Value, isTerminating: isTerminating))
    }

    func windowDidBecomeKey(_ notification: Notification) {
        window?.makeFirstResponder(canvas.text.isEditingText ? window?.firstResponder : canvas)
    }

    func windowDidChangeBackingProperties(_ notification: Notification) { rasterizeForZoom() }

    /// Title-bar proxy icon: drag the flattened image, not the private original.
    func window(_ window: NSWindow, shouldDragDocumentWith event: NSEvent, from dragImageLocation: NSPoint, with pasteboard: NSPasteboard) -> Bool {
        if let view = window.contentView { toolbarController.dragHandle.startDrag(with: event, from: view) }
        return false
    }

    func window(_ window: NSWindow, shouldPopUpDocumentPathMenu menu: NSMenu) -> Bool { false }
}
