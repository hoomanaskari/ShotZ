import ShotzCore
import ShotzUI
import SwiftUI

// Thin adapters from Settings' value types onto ShotzUI components (which work
// on indices and plain toggles). No styling lives here: every look comes from ShotzUI.

extension Binding where Value == Int {
    /// An index binding over an enum value, for `ShotzSegmentedPicker` / `ShotzMenuPicker`.
    @MainActor static func index<E: Equatable>(of value: Binding<E>, in cases: [E]) -> Binding<Int> {
        Binding(
            get: { cases.firstIndex(of: value.wrappedValue) ?? 0 },
            set: { if cases.indices.contains($0) { value.wrappedValue = cases[$0] } }
        )
    }
}

/// The trailing switch of an on/off settings row (label kept for VoiceOver).
struct RowSwitch: View {
    let label: String
    @Binding var isOn: Bool

    init(_ label: String, isOn: Binding<Bool>) {
        self.label = label
        _isOn = isOn
    }

    var body: some View {
        // ShotzSwitchStyle draws its label, so the visible label stays empty
        // (the row shows the title) and the title is the accessibility label.
        Toggle("", isOn: $isOn)
            .toggleStyle(.shotzSwitch)
            .labelsHidden()
            .accessibilityLabel(label)
    }
}

/// A segmented choice over an enum (≤ 4 options).
struct EnumSegmented<E: Hashable>: View {
    let cases: [E]
    let title: (E) -> String
    @Binding var value: E

    var body: some View {
        ShotzSegmentedPicker(cases.map { .init(title: title($0)) }, selection: .index(of: $value, in: cases), size: .compact)
            .fixedSize()
    }
}

/// A menu choice over a list of values.
struct EnumMenu<E: Hashable>: View {
    let cases: [E]
    let title: (E) -> String
    @Binding var value: E

    var body: some View {
        ShotzMenuPicker(cases.map(title), selection: .index(of: $value, in: cases), size: .compact)
    }
}

extension KeyCombo {
    /// Key cap labels: ⌃ ⌥ ⇧ ⌘ then the key.
    var capLabels: [String] { Self.modifierCaps(modifiers) + [Self.keyName(keyCode)] }

    static func modifierCaps(_ m: Modifiers) -> [String] {
        var out: [String] = []
        if m.contains(.control) { out.append("⌃") }
        if m.contains(.option) { out.append("⌥") }
        if m.contains(.shift) { out.append("⇧") }
        if m.contains(.command) { out.append("⌘") }
        return out
    }
}
