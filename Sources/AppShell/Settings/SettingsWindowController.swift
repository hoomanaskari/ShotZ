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
            window.setFrameAutosaveName("ShotzSettings")
            if !window.setFrameUsingName("ShotzSettings") { window.center() }
            self.window = window
        }
        if window?.isVisible != true { context.screenRecording.startPolling() }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
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

struct SettingsRootView: View {
    let context: SettingsContext
    @ObservedObject var selection: SettingsSelection

    var body: some View {
        TabView(selection: $selection.tab) {
            GeneralSettingsView(context: context, settings: context.settings, loginItem: context.loginItem,
                                screenRecording: context.screenRecording)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape") }
                .tag(SettingsTab.general)
            ShortcutsSettingsView(settings: context.settings, hotkeys: context.hotkeys)
                .tabItem { Label(String(localized: "Shortcuts"), systemImage: "command") }
                .tag(SettingsTab.shortcuts)
            QuickAccessSettingsView(settings: context.settings)
                .tabItem { Label(String(localized: "Quick Access"), systemImage: "square.stack") }
                .tag(SettingsTab.quickAccess)
            CaptureSettingsView(settings: context.settings)
                .tabItem { Label(String(localized: "Capture"), systemImage: "camera.aperture") }
                .tag(SettingsTab.capture)
            EditorSettingsView(settings: context.settings)
                .tabItem { Label(String(localized: "Editor"), systemImage: "pencil.and.outline") }
                .tag(SettingsTab.editor)
            AdvancedSettingsView(context: context, settings: context.settings)
                .tabItem { Label(String(localized: "Advanced"), systemImage: "slider.horizontal.3") }
                .tag(SettingsTab.advanced)
        }
        .frame(width: 560, height: 500)
    }
}
