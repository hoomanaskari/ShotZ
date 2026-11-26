import ShotzCore
import ShotzUI
import SwiftUI

struct EditorSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ShotzSettingsPane {
            ShotzSettingsSection(String(localized: "Drawing")) {
                ShotzSettingsRow(String(localized: "Return to the Select tool after drawing")) {
                    RowSwitch(String(localized: "Return to the Select tool after drawing"), isOn: $settings.editorReturnToSelect)
                }
                ShotzSettingsRow(String(localized: "Snap while moving and cropping"),
                                 help: String(localized: "Hold ⌘ while dragging to turn snapping off for a moment.")) {
                    RowSwitch(String(localized: "Snap while moving and cropping"), isOn: $settings.editorSnapping)
                }
            }

            ShotzSettingsSection(String(localized: "Closing"),
                                 footer: String(localized: "Closing the editor puts the capture back in the quick-access stack.")) {
                ShotzSettingsRow(String(localized: "Close the editor after copying")) {
                    RowSwitch(String(localized: "Close the editor after copying"), isOn: $settings.editorCloseAfterCopy)
                }
                ShotzSettingsRow(String(localized: "Close the editor after saving")) {
                    RowSwitch(String(localized: "Close the editor after saving"), isOn: $settings.editorCloseAfterSave)
                }
            }
        }
    }
}
