import SwiftUI

// Swap points for the ShotzUI design system. Every control a Settings or
// onboarding surface shows goes through one of these thin wrappers (or the
// layout wrappers in PrefLayout.swift and KeyCaps.swift), so adopting
// ShotzUI's settings scaffolding means changing these bodies, not the panes:
//
//   PrefPane / PrefSection / PrefRow / PrefHelp  → ShotzUI settings pane, section header, settings row + help
//   ShellCheckbox, ShellSwitch, ShellButton      → ShotzUI controls
//   ShellBanner                                  → ShotzUI inline banner
//   KeyCap / KeyCapsRow / ShortcutRecorderField  → ShotzUI key-cap view
//   StatusPill                                   → ShotzUI status badge
//   ShellIcon                                    → ShotzIcon (already the shared set)

/// A checkbox setting (label to the right of the box).
struct ShellCheckbox: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn)
            .toggleStyle(.checkbox)
    }
}

/// A button in a settings row, footer or onboarding page.
struct ShellButton: View {
    enum Kind { case standard, prominent, link }
    let title: String
    var kind: Kind = .standard
    let action: () -> Void

    init(_ title: String, kind: Kind = .standard, action: @escaping () -> Void) {
        self.title = title
        self.kind = kind
        self.action = action
    }

    var body: some View {
        switch kind {
        case .standard: Button(title, action: action).buttonStyle(.bordered)
        case .prominent: Button(title, action: action).buttonStyle(.borderedProminent)
        case .link: Button(title, action: action).buttonStyle(.link)
        }
    }
}

/// An on/off switch (used where a single prominent choice stands alone).
struct ShellSwitch: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(title, isOn: $isOn).toggleStyle(.switch)
    }
}

/// An inline banner at the top of a pane or section: icon, message and an
/// optional action.
struct ShellBanner: View {
    enum Tone { case info, warning }
    let text: String
    var tone: Tone = .info
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            (tone == .warning ? ShellIcon.warning : ShellIcon.info).view(size: 13)
                .foregroundStyle(tint)
                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 2 }
            Text(text)
                .font(.system(size: 12))
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let actionTitle, let action {
                ShellButton(actionTitle, action: action).controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(tint.opacity(0.25), lineWidth: 0.5))
        .accessibilityElement(children: .combine)
    }

    private var tint: Color { tone == .warning ? .orange : .accentColor }
}
