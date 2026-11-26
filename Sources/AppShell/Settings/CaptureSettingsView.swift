import ShotzCore
import ShotzUI
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ShotzSettingsPane {
            ShotzSettingsSection(String(localized: "Exported files"),
                                 footer: String(localized: "Applies to exported files. ShotZ keeps its own full-resolution PNG of every capture.")) {
                ShotzSettingsRow(String(localized: "Format")) {
                    EnumSegmented(cases: ImageFormat.allCases, title: \.title, value: $settings.exportFormat)
                }
                ShotzSettingsRow(String(localized: "Retina captures")) {
                    EnumMenu(cases: RetinaScale.allCases, title: \.title, value: $settings.retinaScale)
                }
            }

            FileNameSection(settings: settings)

            ShotzSettingsSection(String(localized: "Windows")) {
                ShotzSettingsRow(String(localized: "Include the window's shadow"), help: String(localized: "For window captures (Space in area capture).")) {
                    RowSwitch(String(localized: "Include the window's shadow"), isOn: $settings.windowShadow)
                }
            }
        }
    }
}

struct FileNameSection: View {
    @ObservedObject var settings: SettingsStore
    @State private var draft = ""

    var body: some View {
        ShotzSettingsSection(String(localized: "File name"),
                             footer: String(localized: "%Y year · %m month · %d day · %H hour · %M minute · %S second")) {
            ShotzSettingsRow(String(localized: "Pattern"),
                             help: String(localized: "Example: \(FileNaming.format(draft.isEmpty ? FileNaming.defaultPattern : draft, date: Date())).\(settings.exportFormat.fileExtension)")) {
                // ShotzUI has no text field yet: the system field with ShotZ's value type.
                TextField(String(localized: "File name pattern"), text: $draft)
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(ShotzUI.Typography.value.swiftUIFont)
                    .frame(width: 240)
                    .onAppear { draft = settings.fileNamePattern }
                    .onSubmit(commit)
                    .onChange(of: draft) { commit() }
            }
            if settings.fileNamePattern != FileNaming.defaultPattern {
                ShotzSettingsRow(String(localized: "Default name"), help: FileNaming.defaultPattern) {
                    Button(String(localized: "Restore")) {
                        draft = FileNaming.defaultPattern
                        commit()
                    }
                    .buttonStyle(.shotz(.secondary, size: .compact))
                }
            }
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? FileNaming.defaultPattern : draft
        if value != settings.fileNamePattern { settings.fileNamePattern = value }
    }
}
