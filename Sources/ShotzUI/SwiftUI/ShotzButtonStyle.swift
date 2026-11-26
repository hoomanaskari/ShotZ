import AppKit
import ShotzCore
import SwiftUI

/// SwiftUI counterpart of `ShotzButton` for Settings and onboarding, drawn from the same tokens
/// and the same state → fills mapping.
///
///     Button("Choose…") { … }.buttonStyle(.shotz(.secondary))
///     Button { … } label: { ShotzLabel("Save", icon: .save) }.buttonStyle(.shotz(.primary))
public struct ShotzButtonStyle: ButtonStyle {
    public var role: ShotzUI.ControlRole
    public var size: ShotzUI.ControlSize

    public init(_ role: ShotzUI.ControlRole = .secondary, size: ShotzUI.ControlSize = .regular) {
        self.role = role
        self.size = size
    }

    public func makeBody(configuration: Configuration) -> some View {
        ShotzButtonBody(configuration: configuration, role: role, size: size)
    }
}

extension ButtonStyle where Self == ShotzButtonStyle {
    public static func shotz(_ role: ShotzUI.ControlRole = .secondary, size: ShotzUI.ControlSize = .regular) -> ShotzButtonStyle {
        ShotzButtonStyle(role, size: size)
    }
}

/// Icon + text label for SwiftUI ShotZ buttons (sizes the icon for the control size).
public struct ShotzLabel: View {
    let title: String?
    let icon: ShotzIcon?
    @Environment(\.shotzControlSize) private var size

    public init(_ title: String? = nil, icon: ShotzIcon? = nil) {
        self.title = title
        self.icon = icon
    }

    public var body: some View {
        HStack(spacing: size.iconLabelGap) {
            if let icon { ShotzIconView(icon, size: size.iconSize) }
            if let title { Text(title) }
        }
    }
}

/// A ShotZ icon as a SwiftUI view, tinted by the foreground style.
public struct ShotzIconView: View {
    let icon: ShotzIcon
    let size: CGFloat

    public init(_ icon: ShotzIcon, size: CGFloat = 16) {
        self.icon = icon
        self.size = size
    }

    public var body: some View {
        Image(nsImage: icon.image(pointSize: size))
            .renderingMode(.template)
            .frame(width: size, height: size)
            .accessibilityLabel(icon.accessibilityDescription)
    }
}

private struct ShotzControlSizeKey: EnvironmentKey {
    static let defaultValue: ShotzUI.ControlSize = .regular
}

extension EnvironmentValues {
    public var shotzControlSize: ShotzUI.ControlSize {
        get { self[ShotzControlSizeKey.self] }
        set { self[ShotzControlSizeKey.self] = newValue }
    }
}

private struct ShotzButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let role: ShotzUI.ControlRole
    let size: ShotzUI.ControlSize
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme
    @State private var isHovered = false

    var body: some View {
        // No focus state of its own: the button is focused only by keyboard navigation, and the
        // system draws that ring along `contentShape(.focusEffect, …)`. A click never focuses it.
        let state = ShotzUI.ControlState(isHovered: isHovered, isPressed: configuration.isPressed, isEnabled: isEnabled)
        let fills = ShotzUI.fills(for: role, state: state)
        let shape = RoundedRectangle(cornerRadius: role == .glass ? size.height / 2 : size.radius, style: .continuous)
        configuration.label
            .font(Font(size.font))
            .foregroundStyle(Color(nsColor: fills.content))
            .padding(.horizontal, size.horizontalPadding + 2)
            .frame(minWidth: size.height, minHeight: size.height)
            .background {
                if let bg = fills.background {
                    shape.fill(Color(nsColor: bg))
                        .shadow(color: fills.raised && colorScheme == .light ? .black.opacity(ShotzUI.Elevation.control.opacity) : .clear,
                                radius: ShotzUI.Elevation.control.blur / 2, y: ShotzUI.Elevation.control.offsetY)
                }
            }
            .overlay { if let border = fills.border { shape.strokeBorder(Color(nsColor: border), lineWidth: 1) } }
            .contentShape(.focusEffect, shape)
            .contentShape(Rectangle())
            .frame(minHeight: size.hitHeight)
            .environment(\.shotzControlSize, size)
            .onHover { isHovered = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovered)
    }
}
