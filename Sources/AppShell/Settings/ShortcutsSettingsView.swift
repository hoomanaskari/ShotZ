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

    private let actions: [HotkeyAction] = [
        .captureFullscreen, .captureArea, .captureAllInOne, .captureWindow, .restoreLastClosed,
    ]

    private var captureFailures: Bool {
        hotkeys.hotkeysEnabled
            && [.captureFullscreen, .captureArea, .captureAllInOne].contains { hotkeys.registrationFailures[$0] != nil }
    }

    var body: some View {
        Form {
            Section {
                ForEach(actions, id: \.self) { action in
                    LabeledContent(action.title) {
                        ShortcutRecorder(action: action, settings: settings, hotkeys: hotkeys, recorder: recorder)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Note(String(localized: "Click a shortcut, then press the new keys. Esc cancels, Delete clears it."))
                    Note(String(localized: "If a shortcut does nothing, another app may be using it: macOS does not always tell Shotz when another app holds a shortcut."))
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            if !hotkeys.hotkeysEnabled {
                Section {
                    Note(String(localized: "Started with --no-hotkeys: no shortcuts are registered this run. Changes here are saved."))
                }
            } else if hotkeys.registersNothing {
                Section {
                    Note(String(localized: "No global shortcuts are registered: every shortcut is cleared. Use the menu-bar menu, or set a shortcut above."))
                }
            }

            if captureFailures {
                Section {
                    Note(String(localized: "Another app may already be using some of these shortcuts. Quit it or turn its shortcuts off, or use alternates."), warning: true)
                    Button(HotkeyBindings.alternatesTitle(for: settings.variant)) {
                        for (action, combo) in HotkeyBindings.alternates(for: settings.variant) {
                            settings.setHotkey(combo, for: action)
                        }
                    }
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button(String(localized: "Reset to Defaults")) {
                        recorder.stop()
                        settings.resetHotkeys()
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onDisappear { recorder.stop() }
    }
}

/// One recorder control: the shortcut as a button, a clear button and a
/// warning when the shortcut could not be registered.
struct ShortcutRecorder: View {
    let action: HotkeyAction
    @ObservedObject var settings: SettingsStore
    @ObservedObject var hotkeys: HotkeyCenter
    @ObservedObject var recorder: ShortcutRecorderModel

    private var stored: KeyCombo? { settings.hotkey(for: action) }
    private var isRecording: Bool { recorder.recording == action }

    private var label: String {
        if isRecording {
            let held = KeyNames.modifierGlyphs(recorder.heldModifiers)
            return held.isEmpty ? String(localized: "Type shortcut…") : held + "…"
        }
        return stored.map(KeyNames.display) ?? String(localized: "None")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 6) {
                if let warning = hotkeys.registrationWarning(for: action) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(warning)
                        .accessibilityLabel(warning)
                }
                Button { recorder.toggle(action) } label: {
                    Text(label)
                        .monospacedDigit()
                        .foregroundStyle(stored == nil && !isRecording ? .secondary : .primary)
                        .frame(minWidth: 120)
                }
                .buttonStyle(.bordered)
                .tint(isRecording ? .accentColor : nil)
                .accessibilityLabel(String(localized: "\(action.title) shortcut"))
                .accessibilityValue(label)
                Button { recorder.clear(action) } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .opacity(stored == nil ? 0 : 1)
                .disabled(stored == nil)
                .help(String(localized: "Clear shortcut"))
                .accessibilityLabel(String(localized: "Clear \(action.title) shortcut"))
            }
            if let problem = recorder.problem, problem.action == action {
                Text(problem.message).font(.callout).foregroundStyle(.red)
            }
            if let warning = hotkeys.registrationWarning(for: action) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout).foregroundStyle(.orange)
            }
        }
    }
}
