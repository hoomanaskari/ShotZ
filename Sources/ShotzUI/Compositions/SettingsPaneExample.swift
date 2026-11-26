import ShotzCore
import SwiftUI

/// Reference composition for a Settings pane's content (General), built only from ShotzUI parts:
/// an inline banner, sections with headers over grouped cards, rows with help text and trailing
/// controls, key caps and a status badge. Tabs come from the window's system preferences
/// toolbar (AppShell's `NSToolbar` with `ShotzIcon`), not from this view. Guidance; not wired.
public struct SettingsPaneExample: View {
    @State private var launchAtLogin = true
    @State private var menuBarIcon = false
    @State private var sounds = true
    @State private var showStack = true
    @State private var copy = false
    @State private var save = false
    @State private var format = 0

    public init() {}

    public var body: some View {
        VStack(spacing: 0) {
            ShotzSettingsPane {
                ShotzBanner(String(localized: "This copy is a development build. Launch at login takes effect from the Applications folder."), tone: .info)
                ShotzSettingsSection(String(localized: "Startup")) {
                    ShotzSettingsRow(String(localized: "Launch at login")) { Toggle("", isOn: $launchAtLogin).toggleStyle(.shotzSwitch).labelsHidden() }
                    ShotzSettingsRow(String(localized: "Show menu-bar icon"), help: String(localized: "When hidden, open ShotZ again to reach Settings.")) {
                        Toggle("", isOn: $menuBarIcon).toggleStyle(.shotzSwitch).labelsHidden()
                    }
                    ShotzSettingsRow(String(localized: "Play sounds")) { Toggle("", isOn: $sounds).toggleStyle(.shotzSwitch).labelsHidden() }
                }
                ShotzSettingsSection(String(localized: "Export")) {
                    ShotzSettingsRow(String(localized: "Export folder"), help: "~/Desktop", icon: .folder) {
                        Button(String(localized: "Choose…")) {}.buttonStyle(.shotz(.secondary, size: .compact))
                    }
                    ShotzSettingsRow(String(localized: "Format")) {
                        ShotzSegmentedPicker(["PNG", "JPEG", "HEIC"].map { .init(title: $0) }, selection: $format, size: .compact)
                    }
                }
                ShotzSettingsSection(String(localized: "After capture"), footer: String(localized: "The stack appears at the bottom-left of the display you captured.")) {
                    ShotzSettingsRow(String(localized: "Show quick-access stack")) { Toggle("", isOn: $showStack).toggleStyle(.shotzSwitch).labelsHidden() }
                    ShotzSettingsRow(String(localized: "Copy to clipboard")) { Toggle("", isOn: $copy).toggleStyle(.shotzSwitch).labelsHidden() }
                    ShotzSettingsRow(String(localized: "Save to export folder")) { Toggle("", isOn: $save).toggleStyle(.shotzSwitch).labelsHidden() }
                }
                ShotzSettingsSection(String(localized: "Shortcut")) {
                    ShotzSettingsRow(String(localized: "Capture area")) {
                        HStack(spacing: ShotzUI.Space.s) {
                            ShotzStatusBadge(String(localized: "Registered"), tone: .success)
                            ShotzKeyCapsView(["⌘", "⇧", "4"])
                        }
                    }
                }
            }
        }
        .frame(width: ShotzSettingsMetrics.paneWidth)
        .background(Color(nsColor: ShotzUI.Palette.windowBackground))
    }
}
