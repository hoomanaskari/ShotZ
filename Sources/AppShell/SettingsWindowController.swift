import AppKit
import ShotzCore
import SwiftUI

/// Placeholder Settings window. TODO(engineer A): full tabbed Settings (SPEC §7).
@MainActor public final class SettingsWindowController {
    private let settings: SettingsStore
    private var window: NSWindow?
    /// Called after a setting the shell cares about changes (e.g. menu-bar icon).
    public var onChange: (() -> Void)?

    public init(settings: SettingsStore) {
        self.settings = settings
    }

    public func show() {
        if window == nil {
            let view = SettingsPlaceholderView(settings: settings) { [weak self] in self?.onChange?() }
            let window = NSWindow(contentViewController: NSHostingController(rootView: view))
            window.title = String(localized: "Shotz Settings")
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}

struct SettingsPlaceholderView: View {
    @ObservedObject var settings: SettingsStore
    let onChange: () -> Void

    var body: some View {
        Form {
            Toggle(String(localized: "Show menu-bar icon"), isOn: binding(\.showMenuBarIcon))
            Toggle(String(localized: "Play sounds"), isOn: binding(\.playSounds))
            Toggle(String(localized: "Window capture shadow"), isOn: binding(\.windowShadow))
            LabeledContent(String(localized: "Export folder"), value: settings.exportFolder.path(percentEncoded: false))
            Button(String(localized: "Reset All Settings")) {
                settings.resetAll()
                onChange()
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .padding()
    }

    private func binding(_ keyPath: ReferenceWritableKeyPath<SettingsStore, Bool>) -> Binding<Bool> {
        Binding(
            get: { settings[keyPath: keyPath] },
            set: { settings[keyPath: keyPath] = $0; onChange() }
        )
    }
}
