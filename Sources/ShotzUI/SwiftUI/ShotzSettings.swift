import AppKit
import ShotzCore
import SwiftUI

/// Settings and onboarding scaffolding (SwiftUI). A pane is sections; a section is an optional
/// header above a grouped card; a card holds rows separated by inset hairlines.
///
///     ShotzSettingsPane {
///         ShotzSettingsSection("Startup") {
///             ShotzSettingsRow("Launch at login", help: "…") { Toggle("", isOn: $on).toggleStyle(.shotzSwitch) }
///         }
///     }
public enum ShotzSettingsMetrics {
    public static let paneWidth: CGFloat = 600
    public static let paneInsets = EdgeInsets(top: ShotzUI.Space.xl, leading: ShotzUI.Space.xxl - 4, bottom: ShotzUI.Space.xxl - 4, trailing: ShotzUI.Space.xxl - 4)
    public static let sectionSpacing: CGFloat = 20
    public static let headerToCard: CGFloat = ShotzUI.Space.s
    public static let rowMinHeight: CGFloat = 44
    public static let rowInsets = EdgeInsets(top: 10, leading: ShotzUI.Space.l, bottom: 10, trailing: ShotzUI.Space.l)
}

public struct ShotzSettingsPane<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        VStack(alignment: .leading, spacing: ShotzSettingsMetrics.sectionSpacing) { content }
            .padding(ShotzSettingsMetrics.paneInsets)
            .frame(width: ShotzSettingsMetrics.paneWidth, alignment: .topLeading)
            .fixedSize(horizontal: false, vertical: true)
            .background(Color(nsColor: ShotzUI.Palette.windowBackground))
            .shotzOpensWithoutFocusRing()
    }
}

extension View {
    /// The window holding this view opens with no keyboard focus, so no control shows a ring until
    /// the user presses Tab. Settings panes apply it; use it on other SwiftUI window content.
    public func shotzOpensWithoutFocusRing() -> some View {
        background(OpeningFocusGuard().frame(width: 0, height: 0).accessibilityHidden(true))
    }
}

/// Clears keyboard focus each time its window opens (first key after being shown or reshown).
/// Becoming key again after switching apps keeps whatever the user focused.
private struct OpeningFocusGuard: NSViewRepresentable {
    func makeNSView(context: Context) -> OpeningFocusGuardView { OpeningFocusGuardView() }
    func updateNSView(_ nsView: OpeningFocusGuardView, context: Context) {}
}

@MainActor
final class OpeningFocusGuardView: NSView {
    private var observers: [NSObjectProtocol] = []
    /// True until the window's next becoming key counts as an opening.
    private(set) var opening = true

    override var acceptsFirstResponder: Bool { false }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observers.forEach(NotificationCenter.default.removeObserver)
        observers = []
        guard let window else { return }
        // Joining a window that is already key and visible (a Settings tab switch) is not an opening.
        opening = !(window.isKeyWindow && window.isVisible)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowBecameKey() }
        })
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification, object: window, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.opening = true }
        })
    }

    func windowBecameKey() {
        guard opening, let window else { return }
        opening = false
        ShotzUI.FocusRing.clearOpeningFocus(in: window)
        // SwiftUI may pick its default focus on the next turn; clear that too.
        DispatchQueue.main.async { [weak window] in
            MainActor.assumeIsolated { if let window { ShotzUI.FocusRing.clearOpeningFocus(in: window) } }
        }
    }
}

/// Section header (13 semibold, primary) above a grouped card; optional footer help below.
public struct ShotzSettingsSection<Content: View>: View {
    let title: String?
    let footer: String?
    let content: Content

    public init(_ title: String? = nil, footer: String? = nil, @ViewBuilder content: () -> Content) {
        self.title = title
        self.footer = footer
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ShotzSettingsMetrics.headerToCard) {
            if let title {
                Text(title)
                    .font(ShotzUI.Typography.sectionHeader.swiftUIFont)
                    .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                    .padding(.leading, 2)
                    .accessibilityAddTraits(.isHeader)
            }
            ShotzCard { content }
            if let footer {
                Text(footer)
                    .font(ShotzUI.Typography.caption.swiftUIFont)
                    .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 2)
            }
        }
    }
}

/// A grouped card: raised surface, 10-pt radius, hairline edge; children separated by inset hairlines.
public struct ShotzCard<Content: View>: View {
    let content: Content
    public init(@ViewBuilder content: () -> Content) { self.content = content() }

    public var body: some View {
        let shape = RoundedRectangle(cornerRadius: ShotzUI.Radius.card, style: .continuous)
        VStack(spacing: 0) {
            Group(subviews: content) { subviews in
                ForEach(Array(subviews.enumerated()), id: \.offset) { i, sub in
                    if i > 0 {
                        Rectangle().fill(Color(nsColor: ShotzUI.Palette.separator)).frame(height: 1).padding(.leading, ShotzUI.Space.l)
                    }
                    sub
                }
            }
        }
        .background(shape.fill(Color(nsColor: ShotzUI.Palette.surface)))
        .overlay(shape.strokeBorder(Color(nsColor: ShotzUI.Palette.border), lineWidth: 1))
        .shadow(color: .black.opacity(ShotzUI.Elevation.card.opacity), radius: ShotzUI.Elevation.card.blur / 2, y: ShotzUI.Elevation.card.offsetY)
    }
}

/// A settings row: title (body) with optional help (caption, secondary) and a trailing control.
public struct ShotzSettingsRow<Trailing: View>: View {
    let title: String
    let help: String?
    let icon: ShotzIcon?
    let trailing: Trailing

    public init(_ title: String, help: String? = nil, icon: ShotzIcon? = nil, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.help = help
        self.icon = icon
        self.trailing = trailing()
    }

    public var body: some View {
        HStack(alignment: .center, spacing: ShotzUI.Space.m) {
            if let icon {
                ShotzIconView(icon, size: 16).foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(ShotzUI.Typography.body.swiftUIFont)
                    .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                if let help {
                    Text(help)
                        .font(ShotzUI.Typography.caption.swiftUIFont)
                        .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: ShotzUI.Space.m)
            trailing
        }
        .padding(ShotzSettingsMetrics.rowInsets)
        .frame(minHeight: ShotzSettingsMetrics.rowMinHeight)
        .accessibilityElement(children: .combine)
    }
}

extension ShotzSettingsRow where Trailing == EmptyView {
    public init(_ title: String, help: String? = nil, icon: ShotzIcon? = nil) {
        self.init(title, help: help, icon: icon) { EmptyView() }
    }
}

// MARK: Switch and checkbox

/// ShotZ's switch: 32 × 18 capsule, accent when on, white knob with a soft shadow.
/// `Toggle("Launch at login", isOn: $on).toggleStyle(.shotzSwitch)` (labels hidden in rows).
/// A button underneath: a click never focuses it, so it never leaves a focus ring; keyboard
/// navigation focuses it (ring around the capsule) and Space toggles it.
public struct ShotzSwitchStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        SwitchBody(configuration: configuration)
    }

    private struct SwitchBody: View {
        let configuration: Configuration
        @Environment(\.isEnabled) private var isEnabled
        @Environment(\.labelsVisibility) private var labelsVisibility

        var body: some View {
            let on = configuration.isOn
            let track = on ? Color(nsColor: ShotzUI.Palette.accentFill) : Color(nsColor: ShotzUI.Palette.fillPressed)
            Button { withAnimation(.easeOut(duration: 0.16)) { configuration.isOn.toggle() } } label: {
                HStack(spacing: ShotzUI.Space.s) {
                    // `.labelsHidden()` drops the label and its gap (the switch stands alone in a row).
                    if labelsVisibility != .hidden { configuration.label }
                    ZStack(alignment: on ? .trailing : .leading) {
                        Capsule().fill(track)
                            .overlay(Capsule().strokeBorder(Color(nsColor: ShotzUI.Palette.border), lineWidth: on ? 0 : 1))
                        Circle().fill(.white).padding(2)
                            .shadow(color: .black.opacity(0.18), radius: 1, y: 0.5)
                    }
                    .frame(width: 32, height: 18)
                    .contentShape(.focusEffect, Capsule())
                    .opacity(isEnabled ? 1 : 0.45)
                    .frame(minHeight: 28)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityValue(on ? Text("On") : Text("Off"))
        }
    }
}

/// ShotZ's checkbox: 14-pt rounded square, accent with a white check when on.
public struct ShotzCheckboxStyle: ToggleStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        CheckboxBody(configuration: configuration)
    }

    private struct CheckboxBody: View {
        let configuration: Configuration
        @Environment(\.labelsVisibility) private var labelsVisibility
        var body: some View { shotzCheckboxBody(configuration, showsLabel: labelsVisibility != .hidden) }
    }
}

@MainActor private func shotzCheckboxBody(_ configuration: ToggleStyleConfiguration, showsLabel: Bool) -> some View {
        let on = configuration.isOn
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        return Button { configuration.isOn.toggle() } label: {
            HStack(spacing: ShotzUI.Space.s) {
                ZStack {
                    shape.fill(on ? Color(nsColor: ShotzUI.Palette.accentFill) : Color(nsColor: ShotzUI.Palette.raised))
                    shape.strokeBorder(Color(nsColor: on ? ShotzUI.Palette.accentEdge : ShotzUI.Palette.border), lineWidth: 1)
                    if on { ShotzIconView(.check, size: 11).foregroundStyle(Color(nsColor: ShotzUI.Palette.onAccent)) }
                }
                .frame(width: 14, height: 14)
                .contentShape(.focusEffect, shape)
                if showsLabel {
                    configuration.label
                        .font(ShotzUI.Typography.body.swiftUIFont)
                        .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                }
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(on ? Text("On") : Text("Off"))
}

extension ToggleStyle where Self == ShotzSwitchStyle { public static var shotzSwitch: ShotzSwitchStyle { ShotzSwitchStyle() } }
extension ToggleStyle where Self == ShotzCheckboxStyle { public static var shotzCheckbox: ShotzCheckboxStyle { ShotzCheckboxStyle() } }
