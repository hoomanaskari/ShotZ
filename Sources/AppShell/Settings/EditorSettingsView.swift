import ShotzCore
import SwiftUI

struct EditorSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(String(localized: "Drawing")) {
                Toggle(String(localized: "Return to Select tool after drawing"), isOn: $settings.editorReturnToSelect)
                Toggle(String(localized: "Snap while moving and cropping"), isOn: $settings.editorSnapping)
                Note(String(localized: "Hold ⌘ while dragging to turn snapping off for a moment."))
            }
            Section(String(localized: "Closing")) {
                Toggle(String(localized: "Close editor after copy"), isOn: $settings.editorCloseAfterCopy)
                Toggle(String(localized: "Close editor after save"), isOn: $settings.editorCloseAfterSave)
            }
        }
        .formStyle(.grouped)
    }
}
