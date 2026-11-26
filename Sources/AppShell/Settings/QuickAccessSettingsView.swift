import ShotzCore
import SwiftUI

struct QuickAccessSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        PrefPane {
            PrefSection(title: String(localized: "Placement")) {
                PrefRow(label: String(localized: "Screen edge"), alignment: .center) {
                    Picker("", selection: $settings.quickAccessSide) {
                        ForEach(StackSide.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                PrefRow(label: String(localized: "Display"), alignment: .center) {
                    Picker("", selection: $settings.quickAccessDisplay) {
                        ForEach(StackDisplay.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                PrefRow(label: String(localized: "Card size"), alignment: .center) {
                    Picker("", selection: $settings.quickAccessSize) {
                        ForEach(CardSize.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .fixedSize()
                }
                PrefRow(label: String(localized: "Close cards"), alignment: .center) {
                    Picker("", selection: $settings.quickAccessAutoCloseSeconds) {
                        ForEach(SettingsStore.autoCloseChoices, id: \.self) { seconds in
                            Text(seconds == 0 ? String(localized: "Never automatically") : String(localized: "After \(seconds) seconds")).tag(seconds)
                        }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
            }

            PrefSection(title: String(localized: "Cards")) {
                PrefRow(label: String(localized: "Remove a card")) {
                    Toggle(String(localized: "After dragging it out"), isOn: $settings.quickAccessRemoveAfterDrag)
                    Toggle(String(localized: "After copying"), isOn: $settings.quickAccessCloseAfterCopy)
                    Toggle(String(localized: "After saving"), isOn: $settings.quickAccessCloseAfterSave)
                }
                PrefRow(label: String(localized: "Saving")) {
                    Toggle(String(localized: "Ask where to save each time"), isOn: $settings.askDestinationWhenSaving)
                }
            }
        }
        .toggleStyle(.checkbox)
    }
}
