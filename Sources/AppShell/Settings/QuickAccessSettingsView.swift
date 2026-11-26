import ShotzCore
import SwiftUI

struct QuickAccessSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        Form {
            Section(String(localized: "Placement")) {
                Picker(String(localized: "Side"), selection: $settings.quickAccessSide) {
                    ForEach(StackSide.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Display"), selection: $settings.quickAccessDisplay) {
                    ForEach(StackDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Picker(String(localized: "Size"), selection: $settings.quickAccessSize) {
                    ForEach(CardSize.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker(String(localized: "Auto-close"), selection: $settings.quickAccessAutoCloseSeconds) {
                    ForEach(SettingsStore.autoCloseChoices, id: \.self) { seconds in
                        Text(seconds == 0 ? String(localized: "Off") : String(localized: "After \(seconds) s")).tag(seconds)
                    }
                }
            }

            Section(String(localized: "Cards")) {
                Toggle(String(localized: "Remove after dragging out"), isOn: $settings.quickAccessRemoveAfterDrag)
                Toggle(String(localized: "Close after copy"), isOn: $settings.quickAccessCloseAfterCopy)
                Toggle(String(localized: "Close after save"), isOn: $settings.quickAccessCloseAfterSave)
                Toggle(String(localized: "Ask where to save"), isOn: $settings.askDestinationWhenSaving)
            }
        }
        .formStyle(.grouped)
    }
}
