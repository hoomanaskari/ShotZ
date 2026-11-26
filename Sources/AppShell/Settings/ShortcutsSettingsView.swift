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
        hotkeys.mode == .standard
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
                Note(String(localized: "Click a shortcut, then press the new keys. Esc cancels, Delete clears it."))
            }

            if let note = hotkeys.mode.sessionNote {
                Section {
                    Note(note)
                }
            } else if hotkeys.registersNothing {
                Section {
                    Note(String(localized: "No global shortcuts are registered: every shortcut is cleared. Use the menu-bar menu, or set a shortcut above."))
                }
            }

            if captureFailures {
                Section {
                    Note(String(localized: "Another app may already be using some of these shortcuts. Quit it or turn its shortcuts off, or use alternates."), warning: true)
                    Button(String(localized: "Use ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5")) {
                        settings.setHotkey(.devFullscreen, for: .captureFullscreen)
                        settings.setHotkey(.devArea, for: .captureArea)
                        settings.setHotkey(.devAllInOne, for: .captureAllInOne)
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
                if let status = hotkeys.registrationFailures[action], !hotkeys.isDevOverridden(action) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .help(String(localized: "Couldn't register this shortcut (error \(status)). Another app may be using it."))
                        .accessibilityLabel(String(localized: "Shortcut not registered"))
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
            if hotkeys.isDevOverridden(action) {
                Text(String(localized: "This session: \(hotkeys.binding(for: action).map(KeyNames.display) ?? String(localized: "none"))"))
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }
}
