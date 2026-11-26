import ShotzCore
import SwiftUI

struct ShortcutsSettingsView: View {
    @ObservedObject var settings: SettingsStore
    @ObservedObject var hotkeys: HotkeyCenter
    @StateObject private var recorder: ShortcutRecorderModel

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
        PrefPane {
            if !hotkeys.hotkeysEnabled {
                ShellBanner(text: String(localized: "Test run (--no-hotkeys): no shortcuts are registered. Changes here are saved to this run's settings only."),
                            tone: .warning)
            }
            if captureFailures {
                ShellBanner(
                    text: String(localized: "Another app may be using some of these shortcuts. Quit it or turn its shortcuts off, or use alternates."),
                    tone: .warning,
                    actionTitle: HotkeyBindings.alternatesTitle(for: settings.variant),
                    action: {
                        for (action, combo) in HotkeyBindings.alternates(for: settings.variant) {
                            settings.setHotkey(combo, for: action)
                        }
                    }
                )
            }

            PrefSection(title: String(localized: "Capture")) {
                ForEach(captureActions, id: \.self) { action in
                    row(action)
                }
            }

            PrefSection(title: String(localized: "Quick access")) {
                row(.restoreLastClosed)
            }

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    PrefHelp(String(localized: "Click a shortcut, then press the new keys. Esc cancels, Delete clears it."))
                    PrefHelp(String(localized: "If a shortcut does nothing, another app may be using it: macOS does not always tell ShotZ when another app holds a shortcut."))
                }
                Spacer(minLength: 16)
                ShellButton(String(localized: "Restore Defaults")) {
                    recorder.stop()
                    settings.resetHotkeys()
                }
            }
        }
        .onDisappear { recorder.stop() }
    }

    private func row(_ action: HotkeyAction) -> some View {
        PrefRow(label: action.title, alignment: .center) {
            ShortcutRecorderField(
                combo: settings.hotkey(for: action),
                isRecording: recorder.recording == action,
                heldModifiers: recorder.heldModifiers,
                hasWarning: hotkeys.registrationWarning(for: action) != nil,
                title: action.title,
                onToggle: { recorder.toggle(action) },
                onClear: { recorder.clear(action) }
            )
            if let problem = recorder.problem, problem.action == action {
                PrefHelp(problem.message, tone: .error)
            }
            if let warning = hotkeys.registrationWarning(for: action) {
                PrefHelp(warning, tone: .warning)
            }
        }
    }
}
