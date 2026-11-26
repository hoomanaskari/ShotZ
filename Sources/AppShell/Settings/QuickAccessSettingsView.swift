import ShotzCore
import ShotzUI
import SwiftUI

struct QuickAccessSettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        ShotzSettingsPane {
            ShotzSettingsSection(String(localized: "Placement")) {
                ShotzSettingsRow(String(localized: "Screen edge")) {
                    EnumSegmented(cases: StackSide.allCases, title: \.title, value: $settings.quickAccessSide)
                }
                ShotzSettingsRow(String(localized: "Display")) {
                    EnumMenu(cases: StackDisplay.allCases, title: \.title, value: $settings.quickAccessDisplay)
                }
                ShotzSettingsRow(String(localized: "Card size")) {
                    EnumSegmented(cases: CardSize.allCases, title: \.title, value: $settings.quickAccessSize)
                }
                ShotzSettingsRow(String(localized: "Close cards automatically"), help: String(localized: "The timer pauses while the pointer is over the stack.")) {
                    EnumMenu(cases: SettingsStore.autoCloseChoices,
                             title: { $0 == 0 ? String(localized: "Never") : String(localized: "After \($0) seconds") },
                             value: $settings.quickAccessAutoCloseSeconds)
                }
            }

            ShotzSettingsSection(String(localized: "Cards")) {
                ShotzSettingsRow(String(localized: "Remove after dragging out")) {
                    RowSwitch(String(localized: "Remove after dragging out"), isOn: $settings.quickAccessRemoveAfterDrag)
                }
                ShotzSettingsRow(String(localized: "Close after copying")) {
                    RowSwitch(String(localized: "Close after copying"), isOn: $settings.quickAccessCloseAfterCopy)
                }
                ShotzSettingsRow(String(localized: "Close after saving")) {
                    RowSwitch(String(localized: "Close after saving"), isOn: $settings.quickAccessCloseAfterSave)
                }
                ShotzSettingsRow(String(localized: "Ask where to save each time")) {
                    RowSwitch(String(localized: "Ask where to save each time"), isOn: $settings.askDestinationWhenSaving)
                }
            }
        }
    }
}
