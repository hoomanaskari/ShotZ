import AppKit
import ShotzCore
import SwiftUI

/// The Settings window: SwiftUI tabs hosted in an AppKit window (SPEC §7).
@MainActor public final class SettingsWindowController: NSObject, NSWindowDelegate {
    private let context: SettingsContext
    private let selection = SettingsSelection()
    private var window: NSWindow?

    public init(context: SettingsContext) {
        self.context = context
    }

    public var isVisible: Bool { window?.isVisible ?? false }
    /// For `--debug-snapshot-ui` only: one tab rendered off screen (no window is shown).
    public func debugRender(tab: SettingsTab) async -> Data? {
        let selection = SettingsSelection()
        selection.tab = tab
        return await OffscreenRenderer.png(
            SettingsRootView(context: context, selection: selection),
            size: CGSize(width: 560, height: 500),
            chrome: .init(title: String(localized: "Shotz Settings"), styleMask: [.titled, .closable, .miniaturizable])
        )
    }

    public func show(tab: SettingsTab? = nil) {
        if let tab { selection.tab = tab }
        if window == nil {
            let root = SettingsRootView(context: context, selection: selection)
            let hosting = NSHostingController(rootView: root)
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.title = String(localized: "Shotz Settings")
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.delegate = self
            if let name = WindowPresenter.autosaveName("ShotzSettings") {
                window.setFrameAutosaveName(name)
                if !window.setFrameUsingName(name) { window.center() }
            } else {
                window.center()
            }
            WindowPresenter.prepare(window)
            self.window = window
        }
        if window?.isVisible != true { context.screenRecording.startPolling() }
        if let window { WindowPresenter.bringToFront(window, name: "Settings") }
    }

    public func windowWillClose(_ notification: Notification) {
        context.screenRecording.stopPolling()
        context.hotkeys.isSuspended = false
    }
}

/// Selected tab, shared so `show(tab:)` can switch an open window.
@MainActor final class SettingsSelection: ObservableObject {
    @Published var tab: SettingsTab = .general
}

/// Tabs as a segmented control over the selected pane. (SwiftUI's `TabView`
/// tab strip does not draw in off-screen renders; a segmented picker does,
/// and looks the same.)
struct SettingsRootView: View {
    let context: SettingsContext
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        VStack(spacing: 0) {
            Picker(String(localized: "Settings section"), selection: $selection.tab) {
                ForEach(SettingsTab.allCases, id: \.self) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 4)
            pane
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 560, height: 500)
    }

    @ViewBuilder private var pane: some View {
        switch selection.tab {
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
            AdvancedSettingsView(context: context, settings: context.settings)
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
}
