import AppKit
import ShotzCore
import SwiftUI

/// Inline banner: tinted card with a status glyph, message and optional action.
public struct ShotzBanner: View {
    public enum Tone: Sendable { case info, warning, success, danger }
    let text: String
    let tone: Tone
    let actionTitle: String?
    let action: (() -> Void)?

    public init(_ text: String, tone: Tone = .info, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.tone = tone
        self.actionTitle = actionTitle
        self.action = action
    }

    private var tint: NSColor {
        switch tone {
        case .info: ShotzUI.Palette.selectedContent
        case .warning: ShotzUI.Palette.warning
        case .success: ShotzUI.Palette.success
        case .danger: ShotzUI.Palette.danger
        }
    }
    private var icon: ShotzIcon {
        switch tone {
        case .info: .info
        case .warning: .warning
        case .success: .success
        case .danger: .failure
        }
    }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShotzUI.Radius.card, style: .continuous)
        HStack(alignment: .center, spacing: ShotzUI.Space.m) {
            ShotzIconView(icon, size: 16).foregroundStyle(Color(nsColor: tint))
            Text(text)
                .font(ShotzUI.Typography.body.swiftUIFont)
                .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: ShotzUI.Space.s)
            if let actionTitle, let action {
                Button(actionTitle, action: action).buttonStyle(.shotz(.secondary, size: .compact))
            }
        }
        .padding(.horizontal, ShotzUI.Space.m)
        .padding(.vertical, ShotzUI.Space.s + 2)
        .background(shape.fill(Color(nsColor: tint).opacity(0.10)))
        .overlay(shape.strokeBorder(Color(nsColor: tint).opacity(0.30), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

/// Key caps for shortcuts in Settings and onboarding: ShotzKeyCapsView(["⌃", "⌥", "⌘", "4"]).
public struct ShotzKeyCapsView: View {
    let keys: [String]
    public init(_ keys: [String]) { self.keys = keys }

    public var body: some View {
        HStack(spacing: 3) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                let shape = RoundedRectangle(cornerRadius: ShotzUI.Radius.small, style: .continuous)
                Text(key)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                    .frame(minWidth: 20, minHeight: 20)
                    .padding(.horizontal, key.count > 1 ? 5 : 0)
                    .background(shape.fill(Color(nsColor: ShotzUI.Palette.raised)))
                    .overlay(shape.strokeBorder(Color(nsColor: ShotzUI.Palette.border), lineWidth: 1))
                    .background(shape.fill(Color(nsColor: ShotzUI.Palette.border)).offset(y: 1))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(keys.joined())
    }
}

/// A small status badge: "Granted", "Not granted", "Development build".
public struct ShotzStatusBadge: View {
    public enum Tone: Sendable { case neutral, success, warning, danger }
    let text: String
    let tone: Tone
    public init(_ text: String, tone: Tone = .neutral) { self.text = text; self.tone = tone }

    private var color: NSColor {
        switch tone {
        case .neutral: ShotzUI.Palette.textSecondary
        case .success: ShotzUI.Palette.success
        case .warning: ShotzUI.Palette.warning
        case .danger: ShotzUI.Palette.danger
        }
    }

    public var body: some View {
        HStack(spacing: 5) {
            Circle().fill(Color(nsColor: color)).frame(width: 6, height: 6)
            Text(text).font(ShotzUI.Typography.label.swiftUIFont)
        }
        .foregroundStyle(Color(nsColor: color))
        .padding(.horizontal, ShotzUI.Space.s)
        .frame(height: 20)
        .background(Capsule().fill(Color(nsColor: color).opacity(0.12)))
    }
}

/// Preferences-window tabs: icon above label, selected tab softly tinted (like a selected tool).
public struct ShotzSettingsTabBar: View {
    public struct Tab: Identifiable, Sendable {
        public var id: String { title }
        public var title: String
        public var icon: ShotzIcon
        public init(_ title: String, icon: ShotzIcon) { self.title = title; self.icon = icon }
    }

    let tabs: [Tab]
    @Binding var selection: Int
    @State private var hovered: Int?

    public init(_ tabs: [Tab], selection: Binding<Int>) {
        self.tabs = tabs
        self._selection = selection
    }

    public var body: some View {
        HStack(spacing: ShotzUI.Space.xxs) {
            ForEach(Array(tabs.enumerated()), id: \.offset) { i, tab in
                let selected = i == selection
                let fills = ShotzUI.fills(for: .tool, state: ShotzUI.ControlState(isHovered: hovered == i, isSelected: selected))
                Button { selection = i } label: {
                    VStack(spacing: 3) {
                        ShotzIconView(tab.icon, size: 20)
                        Text(tab.title).font(ShotzUI.Typography.caption.swiftUIFont.weight(selected ? .semibold : .regular))
                    }
                    .foregroundStyle(Color(nsColor: selected ? fills.content : ShotzUI.Palette.textSecondary))
                    .frame(minWidth: 68, minHeight: 50)
                    .padding(.horizontal, 4)
                    .background {
                        if let bg = fills.background {
                            RoundedRectangle(cornerRadius: ShotzUI.ToolMetrics.radius, style: .continuous).fill(Color(nsColor: bg))
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovered = $0 ? i : (hovered == i ? nil : hovered) }
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Segmented picker in pure SwiftUI (Settings, onboarding): same look as the AppKit control,
/// with the raised thumb sliding between segments.
public struct ShotzSegmentedPicker: View {
    let segments: [ShotzSegmentedControl.Segment]
    @Binding var selection: Int
    let size: ShotzUI.ControlSize
    @Namespace private var thumb
    @Environment(\.isEnabled) private var isEnabled

    public init(_ segments: [ShotzSegmentedControl.Segment], selection: Binding<Int>, size: ShotzUI.ControlSize = .regular) {
        self.segments = segments
        self._selection = selection
        self.size = size
    }

    public var body: some View {
        let inner = RoundedRectangle(cornerRadius: size.radius - 2, style: .continuous)
        HStack(spacing: 0) {
            ForEach(Array(segments.enumerated()), id: \.offset) { i, seg in
                let selected = i == selection
                Button { withAnimation(.easeInOut(duration: 0.2)) { selection = i } } label: {
                    HStack(spacing: size.iconLabelGap) {
                        if let icon = seg.icon { ShotzIconView(icon, size: size.iconSize) }
                        if let title = seg.title { Text(title) }
                    }
                    .font(Font(size.font))
                    .foregroundStyle(Color(nsColor: !isEnabled ? ShotzUI.Palette.textTertiary : selected ? ShotzUI.Palette.textPrimary : ShotzUI.Palette.textSecondary))
                    .padding(.horizontal, seg.title == nil ? 0 : size.horizontalPadding)
                    .frame(minWidth: seg.title == nil ? size.height + 4 : size.height * 1.6, maxHeight: .infinity)
                    .background {
                        if selected {
                            inner.fill(Color(nsColor: ShotzUI.Palette.raised))
                                .overlay(inner.strokeBorder(Color(nsColor: ShotzUI.Palette.border), lineWidth: 1))
                                .shadow(color: .black.opacity(ShotzUI.Elevation.control.opacity), radius: 0.75, y: 0.5)
                                .matchedGeometryEffect(id: "thumb", in: thumb)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(seg.label)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(2)
        .frame(height: size.height)
        .background(RoundedRectangle(cornerRadius: size.radius, style: .continuous).fill(Color(nsColor: ShotzUI.Palette.surfaceSunken)))
        .frame(minHeight: size.hitHeight)
    }
}

/// A SwiftUI menu picker drawn like a secondary ShotZ button with an up-down chevron.
public struct ShotzMenuPicker: View {
    let items: [String]
    @Binding var selection: Int
    let size: ShotzUI.ControlSize

    public init(_ items: [String], selection: Binding<Int>, size: ShotzUI.ControlSize = .regular) {
        self.items = items
        self._selection = selection
        self.size = size
    }

    public var body: some View {
        Menu {
            // An inline picker gives the menu its native check marks.
            Picker("", selection: $selection) {
                ForEach(Array(items.enumerated()), id: \.offset) { i, item in Text(item).tag(i) }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            HStack(spacing: size.iconLabelGap) {
                Text(items.indices.contains(selection) ? items[selection] : "")
                Spacer(minLength: 0)
                ShotzIconView(.chevronUpDown, size: size.iconSize - 2).foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
            }
        }
        .menuStyle(.button)
        .buttonStyle(.shotz(.secondary, size: size))
        .menuIndicator(.hidden)
        .fixedSize()
    }
}
