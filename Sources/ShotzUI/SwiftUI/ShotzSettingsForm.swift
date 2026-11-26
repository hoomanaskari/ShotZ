import AppKit
import ShotzCore
import SwiftUI

/// A form row with a right-aligned label column and a control column (A's `PrefRow` layout),
/// for panes that list several controls per setting. Works inside `ShotzCard` or on its own.
public struct ShotzFormRow<Control: View>: View {
    let label: String?
    let labelWidth: CGFloat
    let control: Control

    public init(_ label: String?, labelWidth: CGFloat = 160, @ViewBuilder control: () -> Control) {
        self.label = label
        self.labelWidth = labelWidth
        self.control = control()
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: ShotzUI.Space.m) {
            Text(label ?? "")
                .font(ShotzUI.Typography.body.swiftUIFont)
                .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                .multilineTextAlignment(.trailing)
                .frame(width: labelWidth, alignment: .trailing)
                .accessibilityHidden(label == nil)
            VStack(alignment: .leading, spacing: ShotzUI.Space.xs + 2) { control }
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, ShotzUI.Space.xs)
    }
}

/// Help text under a control (A's `PrefHelp`): secondary, or warning / error with a glyph.
public struct ShotzHelpText: View {
    public enum Tone: Sendable { case secondary, warning, error }
    let text: String
    let tone: Tone
    public init(_ text: String, tone: Tone = .secondary) { self.text = text; self.tone = tone }

    private var color: NSColor {
        switch tone {
        case .secondary: ShotzUI.Palette.textSecondary
        case .warning: ShotzUI.Palette.warning
        case .error: ShotzUI.Palette.danger
        }
    }

    public var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            if tone != .secondary {
                ShotzIconView(tone == .error ? .failure : .warning, size: 12)
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            }
            Text(text)
                .font(ShotzUI.Typography.caption.swiftUIFont)
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Color(nsColor: color))
    }
}

extension ShotzStatusBadge {
    /// A's `StatusPill(text:positive:)`: success when positive, warning otherwise.
    public init(_ text: String, positive: Bool) { self.init(text, tone: positive ? .success : .warning) }
}

/// The shortcut recorder field (A's `ShortcutRecorderField`): key caps for the current shortcut,
/// an accent field while recording (with live modifiers), a warning glyph, and a clear button.
/// Key capture stays with the caller; this view only presents state and reports clicks.
public struct ShotzShortcutField: View {
    let keys: [String]
    let isRecording: Bool
    let heldModifiers: [String]
    let hasWarning: Bool
    let title: String
    let onToggle: () -> Void
    let onClear: () -> Void
    @State private var hovered = false

    public init(keys: [String], isRecording: Bool, heldModifiers: [String] = [], hasWarning: Bool = false, title: String,
                onToggle: @escaping () -> Void, onClear: @escaping () -> Void) {
        self.keys = keys
        self.isRecording = isRecording
        self.heldModifiers = heldModifiers
        self.hasWarning = hasWarning
        self.title = title
        self.onToggle = onToggle
        self.onClear = onClear
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShotzUI.ControlSize.compact.radius, style: .continuous)
        HStack(spacing: ShotzUI.Space.xs) {
            Button(action: onToggle) {
                HStack(spacing: ShotzUI.Space.s - 2) {
                    if isRecording {
                        if !heldModifiers.isEmpty { ShotzKeyCapsView(heldModifiers) }
                        Text(heldModifiers.isEmpty ? String(localized: "Type shortcut…") : "…")
                            .foregroundStyle(Color(nsColor: ShotzUI.Palette.selectedContent))
                    } else if !keys.isEmpty {
                        ShotzKeyCapsView(keys)
                    } else {
                        Text(String(localized: "Record Shortcut")).foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                    }
                    Spacer(minLength: 0)
                    if hasWarning && !isRecording {
                        ShotzIconView(.warning, size: 13).foregroundStyle(Color(nsColor: ShotzUI.Palette.warning))
                    }
                }
                .font(ShotzUI.Typography.label.swiftUIFont)
                .padding(.horizontal, ShotzUI.Space.s)
                .frame(width: 196, height: 26)
                .background(shape.fill(Color(nsColor: isRecording ? ShotzUI.Palette.selectedFill : ShotzUI.Palette.surfaceSunken)))
                .overlay(shape.strokeBorder(Color(nsColor: isRecording ? ShotzUI.Palette.selectedContent : (hovered ? ShotzUI.Palette.textTertiary : ShotzUI.Palette.border)),
                                            lineWidth: isRecording ? 1.5 : 1))
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovered = $0 }
            .accessibilityLabel(String(localized: "\(title) shortcut"))
            .accessibilityValue(isRecording ? String(localized: "Recording") : (keys.isEmpty ? String(localized: "None") : keys.joined()))
            .accessibilityHint(String(localized: "Click, then press the new shortcut. Escape cancels, Delete clears."))

            Button(action: onClear) { ShotzLabel(icon: .close) }
                .buttonStyle(.shotz(.quiet, size: .compact))
                .opacity(keys.isEmpty || isRecording ? 0 : 1)
                .disabled(keys.isEmpty || isRecording)
                .help(String(localized: "Clear shortcut"))
                .accessibilityLabel(String(localized: "Clear \(title) shortcut"))
        }
    }
}
