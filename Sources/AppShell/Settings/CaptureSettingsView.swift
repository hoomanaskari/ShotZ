import ShotzCore
import SwiftUI

struct CaptureSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(String(localized: "Export")) {
                Picker(String(localized: "Format"), selection: $settings.exportFormat) {
                    ForEach(ImageFormat.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Retina scale"), selection: $settings.retinaScale) {
                    ForEach(RetinaScale.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Note(String(localized: "Applies to exported files. Shotz keeps its own copy of every capture as a full-resolution PNG."))
            }

            Section(String(localized: "Capture")) {
                Toggle(String(localized: "Window shadow"), isOn: $settings.windowShadow)
            }

            Section(String(localized: "File name")) {
                FileNamePatternField(settings: settings)
            }
        }
        .formStyle(.grouped)
    }
}

struct FileNamePatternField: View {
    @ObservedObject var settings: SettingsStore
    @State private var draft = ""

    var body: some View {
        LabeledContent(String(localized: "Pattern")) {
            TextField(String(localized: "Pattern"), text: $draft)
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .font(.body.monospaced())
                .onAppear { draft = settings.fileNamePattern }
                .onSubmit(commit)
                .onChange(of: draft) { commit() }
        }
        LabeledContent(String(localized: "Example")) {
            Text(FileNaming.format(draft.isEmpty ? FileNaming.defaultPattern : draft, date: Date()) + "." + settings.exportFormat.fileExtension)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        Note(String(localized: "%Y year, %m month, %d day, %H hour, %M minute, %S second."))
        if settings.fileNamePattern != FileNaming.defaultPattern {
            Button(String(localized: "Restore Default Pattern")) {
                draft = FileNaming.defaultPattern
                commit()
            }
            .buttonStyle(.link)
        }
    }

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let value = trimmed.isEmpty ? FileNaming.defaultPattern : draft
        if value != settings.fileNamePattern { settings.fileNamePattern = value }
    }
}
