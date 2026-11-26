import AppKit
import ShotzCore
import SwiftUI

struct AdvancedSettingsView: View {
    let context: SettingsContext
    @ObservedObject var settings: SettingsStore
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var clearing = false

    var body: some View {
        Form {
            Section(String(localized: "History")) {
                Picker(String(localized: "Keep captures for"), selection: $settings.historyRetention) {
                    ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Note(String(localized: "Older captures are removed when Shotz starts and once a day. Exported files are never touched."))
                HStack {
                    Spacer()
                    Button(String(localized: "Clear History…")) { confirmClear = true }
                        .disabled(clearing)
                }
            }

            Section(String(localized: "Welcome")) {
                HStack {
                    Text(String(localized: "Permissions, system shortcuts and launch at login"))
                    Spacer()
                    Button(String(localized: "Show Welcome Window")) { context.showOnboarding(false) }
                }
            }

            Section {
                HStack {
                    // The only way to quit when the menu-bar icon is hidden.
                    Button(String(localized: "Quit Shotz")) { NSApp.terminate(nil) }
                    Spacer()
                    Button(String(localized: "Reset All Settings…"), role: .destructive) { confirmReset = true }
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            String(localized: "Clear capture history?"),
            isPresented: $confirmClear
        ) {
            Button(String(localized: "Clear History"), role: .destructive) {
                clearing = true
                Task {
                    await context.clearHistory()
                    clearing = false
                }
            }
        } message: {
            Text(String(localized: "All captures kept by Shotz and their edits are deleted. Files you saved or exported stay where they are."))
        }
        .confirmationDialog(
            String(localized: "Reset all settings?"),
            isPresented: $confirmReset
        ) {
            Button(String(localized: "Reset"), role: .destructive) {
                settings.resetAll()   // keeps the onboarding-done flag
            }
        } message: {
            Text(String(localized: "Every setting, including shortcuts, goes back to its default."))
        }
    }
}
