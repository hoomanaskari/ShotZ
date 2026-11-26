import AppKit
import ShotzCore
import SwiftUI

struct GeneralSettingsView: View {
    let context: SettingsContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemController
    @ObservedObject var screenRecording: ScreenRecordingStatus

    var body: some View {
        PrefPane {
            PrefSection {
                PrefRow(label: String(localized: "Startup")) {
                    ShellCheckbox(String(localized: "Launch \(AppVariant.current.displayName) at login"), isOn: Binding(
                        get: { loginItem.isOn },
                        set: { loginItem.setEnabled($0) }
                    ))
                    LoginItemNote(loginItem: loginItem)
                }
                PrefRow(label: String(localized: "Menu bar")) {
                    ShellCheckbox(String(localized: "Show icon in the menu bar"), isOn: $settings.showMenuBarIcon)
                    if !settings.showMenuBarIcon {
                        PrefHelp(String(localized: "Open \(AppVariant.current.displayName) again from Finder or Spotlight to get back to Settings."))
                    }
                }
                PrefRow(label: String(localized: "Sound")) {
                    ShellCheckbox(String(localized: "Play a sound when capturing"), isOn: $settings.playSounds)
                }
            }

            PrefSection(title: String(localized: "After a capture")) {
                PrefRow(label: String(localized: "Then")) {
                    ShellCheckbox(String(localized: "Show it in the quick-access stack"), isOn: $settings.afterCaptureShowQuickAccess)
                    ShellCheckbox(String(localized: "Copy it to the clipboard"), isOn: $settings.afterCaptureCopyToClipboard)
                    ShellCheckbox(String(localized: "Save it to the export folder"), isOn: $settings.afterCaptureSave)
                    if AfterCaptureActions(settings: settings).isSilent {
                        PrefHelp(String(localized: "Captures will only appear in Capture History in the menu."), tone: .warning)
                    }
                }
                PrefRow(label: String(localized: "Export folder")) {
                    ExportFolderPicker(settings: settings)
                }
            }

            PrefSection(title: String(localized: "Permission")) {
                PrefRow(label: String(localized: "Screen Recording"), alignment: .center) {
                    HStack(spacing: 10) {
                        StatusPill(text: screenRecording.isGranted ? String(localized: "Allowed") : String(localized: "Not allowed"),
                                   positive: screenRecording.isGranted)
                        if !screenRecording.isGranted {
                            ShellButton(String(localized: "Set Up…")) { context.showOnboarding(true) }
                                .controlSize(.small)
                        }
                    }
                }
            }
        }
    }
}

struct LoginItemNote: View {
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        switch loginItem.state {
        case .enabled, .disabled:
            EmptyView()
        case .notInstalled:
            PrefHelp(loginItem.variant == .production
                     ? String(localized: "Takes effect when ShotZ runs from the Applications folder.")
                     : String(localized: "Not used in test runs (started with --no-hotkeys)."))
        case .requiresApproval:
            HStack(spacing: 8) {
                PrefHelp(String(localized: "macOS needs you to allow it in Login Items."), tone: .warning)
                ShellButton(String(localized: "Open Login Items…")) { loginItem.openLoginItemsSettings() }
                    .controlSize(.small)
            }
        case .failed(let message):
            PrefHelp(String(localized: "Couldn't change launch at login: \(message)"), tone: .error)
        }
    }
}

/// Folder pop-up in the style of the system's own folder pickers: the folder
/// with its icon, then Other…, Show in Finder and Use Desktop.
struct ExportFolderPicker: View {
    @ObservedObject var settings: SettingsStore

    private var folder: URL { settings.exportFolder }
    private var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }

    var body: some View {
        FolderPopUp(
            folder: folder,
            canReveal: exists,
            showsUseDesktop: folder.standardizedFileURL != ShotzPaths.defaultExportFolder.standardizedFileURL,
            onChoose: choose,
            onReveal: { NSWorkspace.shared.activateFileViewerSelecting([folder]) },
            onUseDesktop: { settings.exportFolder = ShotzPaths.defaultExportFolder }
        )
        .fixedSize()
        if !exists {
            PrefHelp(String(localized: "This folder doesn't exist yet. Saving will create it."), tone: .warning)
        } else {
            PrefHelp(folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
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
