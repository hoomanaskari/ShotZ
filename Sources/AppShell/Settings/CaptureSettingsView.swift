import ShotzCore
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        PrefPane {
            PrefSection(title: String(localized: "Exported files")) {
                PrefRow(label: String(localized: "Format"), alignment: .center) {
                    Picker("", selection: $settings.exportFormat) {
                        ForEach(ImageFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                PrefRow(label: String(localized: "Retina captures")) {
                    Picker("", selection: $settings.retinaScale) {
                        ForEach(RetinaScale.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    PrefHelp(String(localized: "Applies to exported files. Shotz keeps its own full-resolution PNG of every capture."))
                }
                PrefRow(label: String(localized: "File name")) {
                    FileNamePatternField(settings: settings)
                }
            }

            PrefSection(title: String(localized: "Windows")) {
                PrefRow(label: String(localized: "Window captures")) {
                    Toggle(String(localized: "Include the window's shadow"), isOn: $settings.windowShadow)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}

struct FileNamePatternField: View {
    @ObservedObject var settings: SettingsStore
    @State private var draft = ""

    var body: some View {
        TextField(String(localized: "File name pattern"), text: $draft)
            .labelsHidden()
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 12, design: .monospaced))
            .frame(width: 280)
            .onAppear { draft = settings.fileNamePattern }
            .onSubmit(commit)
            .onChange(of: draft) { commit() }
        PrefHelp(String(localized: "Example: \(FileNaming.format(draft.isEmpty ? FileNaming.defaultPattern : draft, date: Date())).\(settings.exportFormat.fileExtension)"))
        PrefHelp(String(localized: "%Y year · %m month · %d day · %H hour · %M minute · %S second"))
        if settings.fileNamePattern != FileNaming.defaultPattern {
            Button(String(localized: "Restore Default Name")) {
                draft = FileNaming.defaultPattern
                commit()
            }
            .buttonStyle(.link)
            .font(.system(size: 11))
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? FileNaming.defaultPattern : draft
        if value != settings.fileNamePattern { settings.fileNamePattern = value }
    }
}
