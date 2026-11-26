import AppKit
import ShotzCore
import ShotzUI
import SwiftUI

struct AdvancedSettingsView: View {
    let context: SettingsContext
    @ObservedObject var settings: SettingsStore
    @State private var confirmClear = false
    @State private var confirmReset = false
    @State private var clearing = false

    private var name: String { AppVariant.current.displayName }

    var body: some View {
        ShotzSettingsPane {
            ShotzSettingsSection(String(localized: "History"),
                                 footer: String(localized: "Older captures are removed when \(name) starts and once a day. Files you saved or exported are never touched.")) {
                ShotzSettingsRow(String(localized: "Keep captures for"), icon: .history) {
                    EnumMenu(cases: HistoryRetention.allCases, title: \.title, value: $settings.historyRetention)
                }
                ShotzSettingsRow(String(localized: "Clear history"), help: String(localized: "Deletes every capture ShotZ keeps and its edits.")) {
                    Button(String(localized: "Clear History…")) { confirmClear = true }
                        .buttonStyle(.shotz(.destructive, size: .compact))
                        .disabled(clearing)
                }
            }

            ShotzSettingsSection(String(localized: "Setup")) {
                ShotzSettingsRow(String(localized: "Welcome guide"),
                                 help: String(localized: "Screen Recording permission, macOS's screenshot shortcuts and launch at login."),
                                 icon: .welcome) {
                    Button(String(localized: "Show…")) { context.showOnboarding(false) }
                        .buttonStyle(.shotz(.secondary, size: .compact))
                }
            }

            ShotzSettingsSection(String(localized: "Reset")) {
                ShotzSettingsRow(String(localized: "Restore all default settings"),
                                 help: String(localized: "Every setting, including shortcuts, goes back to its default. History is kept.")) {
                    Button(String(localized: "Restore…")) { confirmReset = true }
                        .buttonStyle(.shotz(.secondary, size: .compact))
                }
                ShotzSettingsRow(String(localized: "Quit \(name)"), help: String(localized: "The way to quit when the menu-bar icon is hidden."), icon: .quit) {
                    Button(String(localized: "Quit")) { NSApp.terminate(nil) }
                        .buttonStyle(.shotz(.secondary, size: .compact))
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
