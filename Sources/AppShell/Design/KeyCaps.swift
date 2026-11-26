import ShotzCore
import ShotzUI
import SwiftUI

/// The shortcut recorder, composed from ShotzUI: a secondary button showing
/// the shortcut as `ShotzKeyCapsView`; while recording it shows the held
/// modifiers and ShotZ's focus ring; a quiet clear button follows.
struct ShortcutRecorderField: View {
    let combo: KeyCombo?
    let isRecording: Bool
    let heldModifiers: KeyCombo.Modifiers
    let title: String
    let onToggle: () -> Void
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: ShotzUI.Space.xs) {
            Button(action: onToggle) {
                HStack(spacing: ShotzUI.Space.s) {
                    if isRecording {
                        let held = KeyCombo.modifierCaps(heldModifiers)
                        if !held.isEmpty { ShotzKeyCapsView(held) }
                        Text(held.isEmpty ? String(localized: "Type shortcut…") : String(localized: "…"))
                            .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                    } else if let combo {
                        ShotzKeyCapsView(combo.capLabels)
                    } else {
                        Text(String(localized: "Record Shortcut"))
                            .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                    }
                }
                .frame(minWidth: 132)
            }
            .buttonStyle(.shotz(.secondary, size: .regular))
            .overlay {
                if isRecording {
                    RoundedRectangle(cornerRadius: ShotzUI.ControlSize.regular.radius, style: .continuous)
                        .inset(by: -3)
                        .strokeBorder(Color(nsColor: ShotzUI.Palette.focusRing), lineWidth: 3)
                        .allowsHitTesting(false)
                }
            }
            .accessibilityLabel(String(localized: "\(title) shortcut"))
            .accessibilityValue(isRecording ? String(localized: "Recording") : (combo.map(KeyNames.display) ?? String(localized: "None")))
            .accessibilityHint(String(localized: "Click, then press the new shortcut. Escape cancels, Delete clears."))

            Button(action: onClear) { ShotzIconView(.close, size: 12) }
                .buttonStyle(.shotz(.quiet, size: .compact))
                .opacity(combo == nil || isRecording ? 0 : 1)
                .disabled(combo == nil || isRecording)
                .help(String(localized: "Clear shortcut"))
                .accessibilityLabel(String(localized: "Clear \(title) shortcut"))
        }
    }
}
