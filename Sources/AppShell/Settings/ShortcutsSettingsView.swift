import ShotzCore
import ShotzUI
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var hotkeys: HotkeyCenter
    @StateObject private var recorder: ShortcutRecorderModel
    @Environment(\.presentsAsNormalRun) private var presentsAsNormalRun

    init(settings: SettingsStore, hotkeys: HotkeyCenter) {
        self.settings = settings
        self.hotkeys = hotkeys
        _recorder = StateObject(wrappedValue: ShortcutRecorderModel(settings: settings, hotkeys: hotkeys))
    }

    private let captureActions: [HotkeyAction] = [.captureArea, .captureWindow, .captureFullscreen, .captureAllInOne]

    private var captureFailures: Bool {
        hotkeys.hotkeysEnabled
            && [.captureFullscreen, .captureArea, .captureAllInOne].contains { hotkeys.registrationFailures[$0] != nil }
    }

    var body: some View {
        ShotzSettingsPane {
            if !hotkeys.hotkeysEnabled && !presentsAsNormalRun {
                ShotzBanner(String(localized: "Test run (--no-hotkeys): no shortcuts are registered. Changes here are saved to this run's settings only."),
                            tone: .warning)
            }
            if captureFailures {
                ShotzBanner(
                    String(localized: "Another app may be using some of these shortcuts. Quit it or turn its shortcuts off, or use alternates."),
                    tone: .warning,
                    actionTitle: HotkeyBindings.alternatesTitle(for: settings.variant),
                    action: {
                        for (action, combo) in HotkeyBindings.alternates(for: settings.variant) {
                            settings.setHotkey(combo, for: action)
                        }
                    }
                )
            }

            ShotzSettingsSection(String(localized: "Capture")) {
                ForEach(captureActions, id: \.self) { action in row(action) }
            }

            ShotzSettingsSection(
                String(localized: "Quick access"),
                footer: String(localized: "Click a shortcut, then press the new keys. Esc cancels, Delete clears it. If a shortcut does nothing, another app may be using it: macOS does not always tell ShotZ.")
            ) {
                row(.restoreLastClosed)
            }

            HStack {
                Spacer()
                Button(String(localized: "Restore Defaults")) {
                    recorder.stop()
                    settings.resetHotkeys()
                }
                .buttonStyle(.shotz(.secondary, size: .regular))
            }
        }
        .onDisappear { recorder.stop() }
    }

    private func help(for action: HotkeyAction) -> String? {
        if let problem = recorder.problem, problem.action == action { return problem.message }
        return hotkeys.registrationWarning(for: action)
    }

    private func row(_ action: HotkeyAction) -> some View {
        ShotzSettingsRow(action.title, help: help(for: action)) {
            ShotzShortcutField(
                keys: settings.hotkey(for: action)?.capLabels ?? [],
                isRecording: recorder.recording == action,
                heldModifiers: KeyCombo.modifierCaps(recorder.heldModifiers),
                hasWarning: hotkeys.registrationWarning(for: action) != nil,
                title: action.title,
                onToggle: { recorder.toggle(action) },
                onClear: { recorder.clear(action) }
            )
        }
    }
}
