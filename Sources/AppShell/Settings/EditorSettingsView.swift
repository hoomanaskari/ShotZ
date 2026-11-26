import ShotzCore
import SwiftUI

struct EditorSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        PrefPane {
            PrefSection(title: String(localized: "Drawing")) {
                PrefRow(label: String(localized: "Tools")) {
                    ShellCheckbox(String(localized: "Return to the Select tool after drawing"), isOn: $settings.editorReturnToSelect)
                }
                PrefRow(label: String(localized: "Snapping")) {
                    ShellCheckbox(String(localized: "Snap while moving and cropping"), isOn: $settings.editorSnapping)
                    PrefHelp(String(localized: "Hold ⌘ while dragging to turn snapping off for a moment."))
                }
            }

            PrefSection(title: String(localized: "Closing")) {
                PrefRow(label: String(localized: "Close the editor")) {
                    ShellCheckbox(String(localized: "After copying"), isOn: $settings.editorCloseAfterCopy)
                    ShellCheckbox(String(localized: "After saving"), isOn: $settings.editorCloseAfterSave)
                    PrefHelp(String(localized: "Closing the editor puts the capture back in the quick-access stack."))
                }
            }
        }
    }
}
