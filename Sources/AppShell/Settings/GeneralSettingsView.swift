import AppKit
import ShotzCore
import SwiftUI

struct GeneralSettingsView: View {
    let context: SettingsContext
    @ObservedObject var settings: SettingsStore
    @ObservedObject var loginItem: LoginItemController
    @ObservedObject var screenRecording: ScreenRecordingStatus

    var body: some View {
        Form {
            Section {
                Toggle(String(localized: "Launch at login"), isOn: Binding(
                    get: { loginItem.isOn },
                    set: { loginItem.setEnabled($0) }
                ))
                LoginItemNote(loginItem: loginItem)
                Toggle(String(localized: "Show menu-bar icon"), isOn: $settings.showMenuBarIcon)
                if !settings.showMenuBarIcon {
                    Note(String(localized: "With the icon hidden, open Shotz again from Finder or Spotlight to get back to Settings."))
                }
                Toggle(String(localized: "Play sounds"), isOn: $settings.playSounds)
            }

            Section(String(localized: "Export folder")) {
                ExportFolderRow(settings: settings)
            }

            Section(String(localized: "After capture")) {
                Toggle(String(localized: "Show quick-access stack"), isOn: $settings.afterCaptureShowQuickAccess)
                Toggle(String(localized: "Copy to clipboard"), isOn: $settings.afterCaptureCopyToClipboard)
                Toggle(String(localized: "Save to export folder"), isOn: $settings.afterCaptureSave)
                if AfterCaptureActions(settings: settings).isSilent {
                    Note(String(localized: "Captures will only appear in Capture History in the menu."))
                }
            }

            Section(String(localized: "Permissions")) {
                LabeledContent(String(localized: "Screen Recording")) {
                    HStack(spacing: 8) {
                        PermissionBadge(granted: screenRecording.isGranted)
                        if !screenRecording.isGranted {
                            Button(String(localized: "Set Up…")) { context.showOnboarding(true) }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct LoginItemNote: View {
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        switch loginItem.state {
        case .enabled, .disabled:
            EmptyView()
        case .notInstalled:
            Note(String(localized: "Takes effect when Shotz runs from the Applications folder. This copy is a development build."))
        case .requiresApproval:
            HStack {
                Note(String(localized: "macOS needs you to allow Shotz in Login Items."))
                Spacer()
                Button(String(localized: "Open Login Items…")) { loginItem.openLoginItemsSettings() }
            }
        case .failed(let message):
            Note(String(localized: "Couldn't change launch at login: \(message)"), warning: true)
        }
    }
}

struct ExportFolderRow: View {
    @ObservedObject var settings: SettingsStore

    private var folder: URL { settings.exportFolder }
    private var exists: Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: folder.path(percentEncoded: false), isDirectory: &isDir) && isDir.boolValue
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: folder.path(percentEncoded: false)))
                .resizable()
                .frame(width: 20, height: 20)
            Text(folder.path(percentEncoded: false).replacingOccurrences(of: NSHomeDirectory(), with: "~"))
                .lineLimit(1)
                .truncationMode(.middle)
                .help(folder.path(percentEncoded: false))
            Spacer()
            Button(String(localized: "Choose…"), action: choose)
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([folder])
            } label: {
                Image(systemName: "arrow.right.circle")
            }
            .buttonStyle(.borderless)
            .help(String(localized: "Show in Finder"))
            .disabled(!exists)
        }
        if !exists {
            Note(String(localized: "This folder doesn't exist. Saving will create it."), warning: true)
        }
        if folder.standardizedFileURL != ShotzPaths.defaultExportFolder.standardizedFileURL {
            Button(String(localized: "Use Desktop")) { settings.exportFolder = ShotzPaths.defaultExportFolder }
                .buttonStyle(.link)
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
        panel.message = String(localized: "Choose where Shotz saves exported captures.")
        if panel.runModal() == .OK, let url = panel.url {
            settings.exportFolder = url
        }
    }
}

/// Small secondary caption under a setting.
struct Note: View {
    let text: String
    var warning = false

    init(_ text: String, warning: Bool = false) {
        self.text = text
        self.warning = warning
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            if warning {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            }
            Text(text)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct PermissionBadge: View {
    let granted: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(granted ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(granted ? String(localized: "Allowed") : String(localized: "Not allowed"))
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
