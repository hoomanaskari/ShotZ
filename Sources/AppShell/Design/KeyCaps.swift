import ShotzCore
import SwiftUI

/// One key drawn as a small key cap (adapts to light and dark).
struct KeyCap: View {
    let label: String
    var size: CGFloat = 12

    var body: some View {
        Text(label)
            .font(.system(size: size, weight: .medium, design: .rounded))
            .foregroundStyle(.primary)
            .padding(.horizontal, size * 0.42)
            .frame(minWidth: size * 1.75, minHeight: size * 1.65)
            .background(
                RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
                    .fill(Color(nsColor: .controlColor))
                    .shadow(color: .black.opacity(0.22), radius: 0, x: 0, y: 1)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.36, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 0.5)
            )
    }
}

/// A shortcut as a row of key caps: ⌃ ⌥ ⇧ ⌘ then the key.
struct KeyCapsRow: View {
    let combo: KeyCombo?
    var modifiersOnly: KeyCombo.Modifiers? = nil
    var size: CGFloat = 12

    static func caps(for combo: KeyCombo) -> [String] {
        glyphs(for: combo.modifiers) + [KeyCombo.keyName(combo.keyCode)]
    }

    static func glyphs(for m: KeyCombo.Modifiers) -> [String] {
        var out: [String] = []
        if m.contains(.control) { out.append("⌃") }
        if m.contains(.option) { out.append("⌥") }
        if m.contains(.shift) { out.append("⇧") }
        if m.contains(.command) { out.append("⌘") }
        return out
    }

    var body: some View {
        HStack(spacing: size * 0.3) {
            let labels = combo.map(Self.caps(for:)) ?? Self.glyphs(for: modifiersOnly ?? [])
            ForEach(Array(labels.enumerated()), id: \.offset) { _, label in
                KeyCap(label: label, size: size)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(combo.map(KeyNames.display) ?? "")
    }
}

/// The shortcut recorder control: shows the shortcut as key caps; click to
/// record (accent ring, live modifiers), clear button, warning badge.
struct ShortcutRecorderField: View {
    let combo: KeyCombo?
    let isRecording: Bool
    let heldModifiers: KeyCombo.Modifiers
    let hasWarning: Bool
    let title: String
    let onToggle: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    if isRecording {
                        if !heldModifiers.isEmpty {
                            KeyCapsRow(combo: nil, modifiersOnly: heldModifiers, size: 11)
                        }
                        Text(heldModifiers.isEmpty ? String(localized: "Type shortcut…") : String(localized: "…"))
                            .foregroundStyle(.secondary)
                    } else if let combo {
                        KeyCapsRow(combo: combo, size: 11)
                    } else {
                        Text(String(localized: "Record Shortcut")).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    if hasWarning && !isRecording {
                        ShellIcon.warning.image.foregroundStyle(.orange).font(.system(size: 11))
                    }
                }
                .font(.system(size: 12))
                .padding(.horizontal, 8)
                .frame(width: 196, height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(isRecording ? Color.accentColor.opacity(0.10) : Color(nsColor: .textBackgroundColor))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                                      lineWidth: isRecording ? 2 : 1)
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(String(localized: "\(title) shortcut"))
            .accessibilityValue(isRecording ? String(localized: "Recording") : (combo.map(KeyNames.display) ?? String(localized: "None")))
            .accessibilityHint(String(localized: "Click, then press the new shortcut. Escape cancels, Delete clears."))

            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
            }
            .buttonStyle(.borderless)
            .opacity(combo == nil || isRecording ? 0 : 1)
            .disabled(combo == nil || isRecording)
            .help(String(localized: "Clear shortcut"))
            .accessibilityLabel(String(localized: "Clear \(title) shortcut"))
        }
    }
}
