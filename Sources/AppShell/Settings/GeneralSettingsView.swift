import AppKit
import ShotzCore
import ShotzUI
import SwiftUI

struct GeneralSettingsView: View {
    let context: SettingsContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemController
    @ObservedObject var screenRecording: ScreenRecordingStatus

    private var name: String { AppVariant.current.displayName }

    var body: some View {
        ShotzSettingsPane {
            LoginItemBanner(loginItem: loginItem)

            ShotzSettingsSection(String(localized: "Startup")) {
                ShotzSettingsRow(String(localized: "Launch at login")) {
                    RowSwitch(String(localized: "Launch at login"), isOn: Binding(get: { loginItem.isOn }, set: { loginItem.setEnabled($0) }))
                }
                ShotzSettingsRow(String(localized: "Show icon in the menu bar"),
                                 help: settings.showMenuBarIcon ? nil : String(localized: "When hidden, open \(name) again from Finder or Spotlight to reach Settings.")) {
                    RowSwitch(String(localized: "Show icon in the menu bar"), isOn: $settings.showMenuBarIcon)
                }
                ShotzSettingsRow(String(localized: "Play a sound when capturing")) {
                    RowSwitch(String(localized: "Play a sound when capturing"), isOn: $settings.playSounds)
                }
            }

            ShotzSettingsSection(String(localized: "After a capture"),
                                 footer: AfterCaptureActions(settings: settings).isSilent
                                    ? String(localized: "With all three off, captures only appear in Capture History in the menu.") : nil) {
                ShotzSettingsRow(String(localized: "Show it in the quick-access stack")) {
                    RowSwitch(String(localized: "Show it in the quick-access stack"), isOn: $settings.afterCaptureShowQuickAccess)
                }
                ShotzSettingsRow(String(localized: "Copy it to the clipboard")) {
                    RowSwitch(String(localized: "Copy it to the clipboard"), isOn: $settings.afterCaptureCopyToClipboard)
                }
                ShotzSettingsRow(String(localized: "Save it to the export folder")) {
                    RowSwitch(String(localized: "Save it to the export folder"), isOn: $settings.afterCaptureSave)
                }
            }

            ShotzSettingsSection(String(localized: "Export")) {
                ExportFolderRow(settings: settings)
            }

            ShotzSettingsSection(String(localized: "Permission")) {
                ShotzSettingsRow(String(localized: "Screen Recording"), icon: .permission) {
                    HStack(spacing: ShotzUI.Space.s) {
                        ShotzStatusBadge(screenRecording.isGranted ? String(localized: "Allowed") : String(localized: "Not allowed"),
                                         tone: screenRecording.isGranted ? .success : .warning)
                        if !screenRecording.isGranted {
                            Button(String(localized: "Set Up…")) { context.showOnboarding(true) }
                                .buttonStyle(.shotz(.secondary, size: .compact))
                        }
                    }
                }
            }
        }
    }
}

/// Launch-at-login notices as a ShotzUI banner above the sections.
struct LoginItemBanner: View {
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        switch loginItem.state {
        case .enabled, .disabled:
            EmptyView()
        case .notInstalled:
            ShotzBanner(loginItem.variant == .production
                        ? String(localized: "Launch at login takes effect when ShotZ runs from the Applications folder.")
                        : String(localized: "This is a test run (--no-hotkeys): launch at login is not used."),
                        tone: .info)
        case .requiresApproval:
            ShotzBanner(String(localized: "macOS needs you to allow \(AppVariant.current.displayName) in Login Items."),
                        tone: .warning, actionTitle: String(localized: "Open Login Items…"),
                        action: { loginItem.openLoginItemsSettings() })
        case .failed(let message):
            ShotzBanner(String(localized: "Couldn't change launch at login: \(message)"), tone: .danger)
        }
    }
}

/// Export folder: folder icon, title, the path as help, Show in Finder and Choose….
struct ExportFolderRow: View {
    @ObservedObject var settings: SettingsStore

    private var folder: URL { settings.exportFolder }
    private var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }
    private var isDesktop: Bool { folder.standardizedFileURL == ShotzPaths.defaultExportFolder.standardizedFileURL }

    var body: some View {
        let path = folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~")
        ShotzSettingsRow(String(localized: "Export folder"),
                         help: exists ? path : String(localized: "\(path): doesn't exist yet; saving creates it."),
                         icon: .folder) {
            HStack(spacing: ShotzUI.Space.xs) {
                if !isDesktop {
                    Button(String(localized: "Use Desktop")) { settings.exportFolder = ShotzPaths.defaultExportFolder }
                        .buttonStyle(.shotz(.quiet, size: .compact))
                }
                Button { NSWorkspace.shared.activateFileViewerSelecting([folder]) } label: { ShotzIconView(.showInFinder, size: 14) }
                    .buttonStyle(.shotz(.quiet, size: .compact))
                    .disabled(!exists)
                    .help(String(localized: "Show in Finder"))
                    .accessibilityLabel(String(localized: "Show in Finder"))
                Button(String(localized: "Choose…"), action: choose)
                    .buttonStyle(.shotz(.secondary, size: .compact))
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = folder
        panel.prompt = String(localized: "Use Folder")
        panel.message = String(localized: "Choose where ShotZ saves exported captures.")
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportFolder = url
        }
    }
}
