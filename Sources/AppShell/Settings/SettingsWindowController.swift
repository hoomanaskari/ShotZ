import AppKit
import ShotzCore
import ShotzUI
import SwiftUI

/// The Settings window (SPEC §7): a standard preferences window with toolbar
/// tabs (icon + label). The title follows the tab, and the window animates its
/// height to fit each pane, so short panes never scroll. ⌘1…⌘6 switch tabs,
/// ⌘W closes.
@MainActor public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let context: SettingsContext
    private var window: ShellWindow?
    private var tabs: SettingsTabViewController?

    public init(context: SettingsContext) {
        self.context = context
    }

    public var isVisible: Bool { window?.isVisible ?? false }

    public func show(tab: SettingsTab? = nil) {
        if window == nil {
            let tabs = SettingsTabViewController(context: context)
            let window = Self.makeWindow(tabs: tabs)
            window.delegate = self
            window.setFrameAutosaveName("ShotzSettings")
            if !window.setFrameUsingName("ShotzSettings") { window.center() }
            WindowPresenter.prepare(window)
            self.tabs = tabs
            self.window = window
        }
        if let tab { tabs?.select(tab) }
        tabs?.fitWindowToSelection(animate: false)
        if window?.isVisible != true { context.screenRecording.startPolling() }
        if let window { WindowPresenter.bringToFront(window, name: "Settings") }
    }

    public func windowWillClose(_ notification: Notification) {
        context.screenRecording.stopPolling()
        context.hotkeys.isSuspended = false
    }

    static func makeWindow(tabs: SettingsTabViewController) -> ShellWindow {
        let window = ShellWindow(contentRect: NSRect(x: 0, y: 0, width: ShotzSettingsMetrics.paneWidth, height: 400),
                                 styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        window.contentViewController = tabs
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.onSelectIndex = { [weak tabs] index in
            guard let tabs, SettingsTab.allCases.indices.contains(index) else { return }
            tabs.select(SettingsTab.allCases[index])
        }
        return window
    }

    /// For `--debug-snapshot-ui`: one tab in its own off-screen window (never
    /// ordered in), in the given appearance.
    /// Snapshots show the installed app's updates section (`SoftwareUpdates.preview`),
    /// not the test run's "updates are off" note; `updates` overrides that.
    public func debugRender(tab: SettingsTab, appearance: NSAppearance.Name = .aqua, scale: CGFloat = 2,
                            updates: SoftwareUpdates = .preview(.available)) async -> Data? {
        let c = context
        let shown = SettingsContext(settings: c.settings, hotkeys: c.hotkeys, loginItem: c.loginItem,
                                    screenRecording: c.screenRecording, clearHistory: c.clearHistory,
                                    showOnboarding: c.showOnboarding, updates: updates)
        let tabs = SettingsTabViewController(context: shown, presentsAsNormalRun: true)
        let window = Self.makeWindow(tabs: tabs)
        window.appearance = NSAppearance(named: appearance)
        tabs.select(tab)
        tabs.fitWindowToSelection(animate: false)
        return await OffscreenRenderer.capture(window, scale: scale)
    }
}

/// Toolbar-style tabs, one hosting controller per pane.
final class SettingsTabViewController: NSTabViewController {
    /// Pane width from ShotzUI's settings metrics (the window is this wide).
    static let paneWidth = ShotzSettingsMetrics.paneWidth
    private let context: SettingsContext

    init(context: SettingsContext, presentsAsNormalRun: Bool = false) {
        self.context = context
        super.init(nibName: nil, bundle: nil)
        tabStyle = .toolbar
        transitionOptions = [.crossfade]
        for tab in SettingsTab.allCases {
            let hosting = NSHostingController(rootView: AnyView(pane(for: tab).environment(\.presentsAsNormalRun, presentsAsNormalRun)))
            hosting.sizingOptions = []
            let item = NSTabViewItem(viewController: hosting)
            item.label = tab.title
            item.image = tab.icon.toolbarImage()
            item.identifier = tab.rawValue
            addTabViewItem(item)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    func select(_ tab: SettingsTab) {
        guard let index = SettingsTab.allCases.firstIndex(of: tab) else { return }
        selectedTabViewItemIndex = index
    }

    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        fitWindowToSelection(animate: view.window?.isVisible == true)
    }

    /// Sizes the window to the selected pane, keeping its top edge in place.
    func fitWindowToSelection(animate: Bool) {
        guard let item = tabViewItems[safe: selectedTabViewItemIndex],
              let hosting = item.viewController as? NSHostingController<AnyView>,
              let window = view.window else { return }
        window.title = item.label
        // Ask SwiftUI for the pane's natural height at the fixed width (the
        // hosting view's own fitting size is bounded by its current frame).
        let ideal = hosting.sizeThatFits(in: CGSize(width: ShotzSettingsMetrics.paneWidth, height: 10_000))
        let size = NSSize(width: ShotzSettingsMetrics.paneWidth, height: ceil(ideal.height))
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin = NSPoint(x: window.frame.minX, y: window.frame.maxY - frame.height)
        if frame.size != window.frame.size {
            window.setFrame(frame, display: true, animate: animate)
        }
    }

    @ViewBuilder private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general:
            GeneralSettingsView(context: context, settings: context.settings, loginItem: context.loginItem,
                                screenRecording: context.screenRecording)
        case .shortcuts:
            ShortcutsSettingsView(settings: context.settings, hotkeys: context.hotkeys)
        case .quickAccess:
            QuickAccessSettingsView(settings: context.settings)
        case .capture:
            CaptureSettingsView(settings: context.settings)
        case .editor:
            EditorSettingsView(settings: context.settings)
        case .advanced:
            AdvancedSettingsView(context: context, settings: context.settings, updates: context.updates)
        }
    }
}

extension SettingsTab {
    var title: String {
        switch self {
        case .general: String(localized: "General")
        case .shortcuts: String(localized: "Shortcuts")
        case .quickAccess: String(localized: "Quick Access")
        case .capture: String(localized: "Capture")
        case .editor: String(localized: "Editor")
        case .advanced: String(localized: "Advanced")
        }
    }

    var icon: ShellIcon {
        switch self {
        case .general: .general
        case .shortcuts: .shortcuts
        case .quickAccess: .quickAccess
        case .capture: .capture
        case .editor: .editor
        case .advanced: .advanced
        }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
