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
        PrefPane {
            PrefSection(title: String(localized: "History")) {
                PrefRow(label: String(localized: "Keep captures for")) {
                    Picker("", selection: $settings.historyRetention) {
                        ForEach(HistoryRetention.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    PrefHelp(String(localized: "Older captures are removed when \(AppVariant.current.displayName) starts and once a day. Files you saved or exported are never touched."))
                }
                PrefRow(label: nil) {
                    ShellButton(String(localized: "Clear History…")) { confirmClear = true }
                        .disabled(clearing)
                }
            }

            PrefSection(title: String(localized: "Setup")) {
                PrefRow(label: String(localized: "Welcome guide")) {
                    ShellButton(String(localized: "Show Welcome Window…")) { context.showOnboarding(false) }
                    PrefHelp(String(localized: "Screen Recording permission, macOS's screenshot shortcuts and launch at login."))
                }
            }

            PrefSection(title: String(localized: "Reset")) {
                PrefRow(label: String(localized: "Settings")) {
                    ShellButton(String(localized: "Restore All Defaults…")) { confirmReset = true }
                    PrefHelp(String(localized: "Every setting, including shortcuts, goes back to its default. History is kept."))
                }
                PrefRow(label: AppVariant.current.displayName) {
                    // The only way to quit when the menu-bar icon is hidden.
                    ShellButton(String(localized: "Quit \(AppVariant.current.displayName)")) { NSApp.terminate(nil) }
                }
            }
        }
        .confirmationDialog(String(localized: "Clear capture history?"), isPresented: $confirmClear) {
            Button(String(localized: "Clear History"), role: .destructive) {
                clearing = true
                Task {
                    await context.clearHistory()
                    clearing = false
                }
            }
        } message: {
            Text(String(localized: "All captures kept by ShotZ and their edits are deleted. Files you saved or exported stay where they are."))
        }
        .confirmationDialog(String(localized: "Restore all default settings?"), isPresented: $confirmReset) {
            Button(String(localized: "Restore Defaults"), role: .destructive) {
                settings.resetAll()   // keeps the onboarding-done flag
            }
        } message: {
            Text(String(localized: "Every setting, including shortcuts, goes back to its default."))
        }
    }
}
