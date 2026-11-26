import AppKit
import ShotzCore
import ShotzUI
import SwiftUI

/// The welcome window: a sidebar with the steps (progress), the step's
/// illustration, title, text and actions, and Back / Continue at the bottom.
/// Controls, type, spacing and colour come from ShotzUI.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    static let size = CGSize(width: 700, height: 500)

    var body: some View {
        HStack(spacing: 0) {
            StepSidebar(current: model.step)
                .frame(width: 214)
            Rectangle().fill(Color(nsColor: ShotzUI.Palette.separator)).frame(width: 1)
            VStack(spacing: 0) {
                Group {
                    switch model.step {
                    case .welcome: WelcomePage(model: model)
                    case .screenRecording: ScreenRecordingPage(model: model, status: model.screenRecording)
                    case .systemShortcuts: SystemShortcutsPage(model: model)
                    case .launchAtLogin: LaunchAtLoginPage(model: model, loginItem: model.loginItem)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, ShotzUI.Space.xxl)
                .padding(.top, ShotzUI.Space.xxl + ShotzUI.Space.s)

                HStack(spacing: ShotzUI.Space.s) {
                    Text(String(localized: "Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
                        .font(ShotzUI.Typography.caption.swiftUIFont)
                        .foregroundStyle(Color(nsColor: ShotzUI.Palette.textTertiary))
                    Spacer()
                    if !model.isFirst {
                        Button(String(localized: "Back")) { model.back() }
                            .buttonStyle(.shotz(.secondary, size: .large))
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(model.isLast ? String(localized: "Done") : String(localized: "Continue")) { model.next() }
                        .buttonStyle(.shotz(.primary, size: .large))
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, ShotzUI.Space.xl)
                .padding(.vertical, ShotzUI.Space.l)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(Color(nsColor: ShotzUI.Palette.windowBackground))
    }
}

private struct StepSidebar: View {
    let current: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: ShotzUI.Space.m) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                Text(AppVariant.current.displayName)
                    .font(ShotzUI.Typography.title.swiftUIFont)
                    .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
            }
            .padding(.top, ShotzUI.Space.xxl + ShotzUI.Space.m)
            .padding(.bottom, ShotzUI.Space.xl)

            VStack(alignment: .leading, spacing: ShotzUI.Space.xs) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    StepRow(step: step, state: step == current ? .current : (step.rawValue < current.rawValue ? .done : .upcoming))
                }
            }
            Spacer()
        }
        .padding(.horizontal, ShotzUI.Space.l)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: ShotzUI.Palette.surfaceSunken))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Steps"))
    }
}

private struct StepRow: View {
    enum State { case done, current, upcoming }
    let step: OnboardingStep
    let state: State

    var body: some View {
        let fills = ShotzUI.fills(for: .tool, state: ShotzUI.ControlState(isSelected: state == .current))
        HStack(spacing: ShotzUI.Space.s + 2) {
            ZStack {
                Circle()
                    .fill(state == .upcoming ? Color.clear : Color(nsColor: ShotzUI.Palette.accentFill))
                    .overlay(Circle().strokeBorder(state == .upcoming ? Color(nsColor: ShotzUI.Palette.border) : Color.clear, lineWidth: 1))
                if state == .done {
                    ShotzIconView(.check, size: 11).foregroundStyle(Color(nsColor: ShotzUI.Palette.onAccent))
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(ShotzUI.Typography.label.swiftUIFont)
                        .foregroundStyle(Color(nsColor: state == .current ? ShotzUI.Palette.onAccent : ShotzUI.Palette.textSecondary))
                }
            }
            .frame(width: 20, height: 20)
            Text(step.title)
                .font(state == .current ? ShotzUI.Typography.sectionHeader.swiftUIFont : ShotzUI.Typography.body.swiftUIFont)
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(Color(nsColor: state == .upcoming ? ShotzUI.Palette.textSecondary : ShotzUI.Palette.textPrimary))
            Spacer()
        }
        .padding(.vertical, ShotzUI.Space.s - 2)
        .padding(.horizontal, ShotzUI.Space.s)
        .background {
            if state == .current, let bg = fills.background {
                RoundedRectangle(cornerRadius: ShotzUI.ToolMetrics.radius, style: .continuous).fill(Color(nsColor: bg))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(step.title)
        .accessibilityValue(state == .current ? String(localized: "Current step") : state == .done ? String(localized: "Done") : "")
    }
}

/// Title + body under the illustration, shared by every page.
private struct PageText: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: ShotzUI.Space.s) {
            Text(title)
                .font(ShotzUI.Typography.display.swiftUIFont)
                .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                .accessibilityAddTraits(.isHeader)
            Text(message)
                .font(ShotzUI.Typography.body.swiftUIFont)
                .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Secondary note text (caption).
private struct Note: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(ShotzUI.Typography.caption.swiftUIFont)
            .foregroundStyle(Color(nsColor: ShotzUI.Palette.textSecondary))
            .fixedSize(horizontal: false, vertical: true)
    }
}

extension OnboardingStep {
    var title: String {
        switch self {
        case .welcome: String(localized: "Welcome")
        case .screenRecording: String(localized: "Screen Recording")
        case .systemShortcuts: String(localized: "Shortcuts")
        case .launchAtLogin: String(localized: "Launch at Login")
        }
    }
}

struct WelcomePage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(alignment: .leading, spacing: ShotzUI.Space.l) {
            WelcomeIllustration()
            PageText(
                title: String(localized: "Welcome to \(AppVariant.current.displayName)"),
                message: String(localized: "Take a screenshot, find it waiting in the corner of your screen, mark it up, and drop it wherever it needs to go.")
            )
            VStack(alignment: .leading, spacing: ShotzUI.Space.s) {
                ForEach([HotkeyAction.captureArea, .captureFullscreen, .captureAllInOne], id: \.self) { action in
                    HStack {
                        Text(action.title)
                            .font(ShotzUI.Typography.body.swiftUIFont)
                            .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                        Spacer()
                        // The stored shortcut: what the user gets (even if this run has --no-hotkeys).
                        if let combo = model.settings.hotkey(for: action) {
                            ShotzKeyCapsView(combo.capLabels)
                        } else {
                            Note(String(localized: "No shortcut"))
                        }
                    }
                }
            }
            .frame(maxWidth: 340)
        }
    }
}

struct ScreenRecordingPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var status: ScreenRecordingStatus
    private var name: String { AppVariant.current.displayName }

    var body: some View {
        // The look-alike entries note adds a banner; tighter spacing keeps the page in the window.
        let note = model.showsDuplicateEntryNote(granted: status.isGranted)
        VStack(alignment: .leading, spacing: note ? ShotzUI.Space.s : ShotzUI.Space.l) {
            ScreenRecordingIllustration(granted: status.isGranted)
            PageText(
                title: model.reason == .permissionMissing
                    ? String(localized: "\(name) needs Screen Recording")
                    : String(localized: "Allow Screen Recording"),
                message: String(localized: "macOS only lets apps see what's on screen with your permission. ShotZ uses it for screenshots and nothing else: no recording, no network.")
            )
            HStack(spacing: ShotzUI.Space.m) {
                ShotzStatusBadge(status.isGranted ? String(localized: "Screen Recording is allowed") : String(localized: "Not allowed yet"),
                                 tone: status.isGranted ? .success : .warning)
                if !status.isGranted {
                    Button(String(localized: "Open System Settings")) {
                        // Makes ShotZ appear in the list (first time only), then
                        // opens Privacy & Security ▸ Screen & System Audio Recording.
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                    .buttonStyle(.shotz(.secondary, size: .regular))
                }
            }
            if note {
                ShotzBanner(String(localized: "If ShotZ appears twice in the list, the older entry is from a previous version. Turn on the one for this copy, or remove both with − and add ShotZ from Applications with +."),
                            tone: .info)
            }
            Note(status.isGranted
                 ? String(localized: "If captures still fail, relaunch so macOS applies the permission.")
                 : note
                    ? String(localized: "If macOS asks to quit and reopen it, choose Later, then relaunch here.")
                    : String(localized: "Turn on \(name) in the list. If macOS asks to quit and reopen it, choose Later, then relaunch here."))
            Button(String(localized: "Relaunch \(name)")) { Permissions.relaunch() }
                .buttonStyle(.shotz(.secondary, size: .regular))
        }
    }
}

struct SystemShortcutsPage: View {
    @ObservedObject var model: OnboardingModel
    @Environment(\.presentsAsNormalRun) private var presentsAsNormalRun

    var body: some View {
        let shortcuts = model.systemShortcuts
        let combos = [HotkeyAction.captureFullscreen, .captureArea, .captureAllInOne].compactMap { model.settings.hotkey(for: $0) }
        VStack(alignment: .leading, spacing: ShotzUI.Space.m) {
            ShortcutsIllustration(combos: combos, allClear: !shortcuts.anyEnabled)
            PageText(
                title: String(localized: "Screenshot shortcuts"),
                message: shortcuts.anyEnabled
                    ? String(localized: "macOS's own screenshot shortcuts are on, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 won't reach ShotZ yet.")
                    : String(localized: "macOS's own screenshot shortcuts are off, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 can reach ShotZ.")
            )
            if shortcuts.anyEnabled {
                VStack(alignment: .leading, spacing: ShotzUI.Space.xs) {
                    Text(String(localized: "System Settings ▸ Keyboard ▸ Keyboard Shortcuts… ▸ Screenshots, untick:"))
                        .font(ShotzUI.Typography.label.swiftUIFont)
                        .foregroundStyle(Color(nsColor: ShotzUI.Palette.textPrimary))
                    ForEach(shortcuts.enabledItems) { item in Note("\(item.shortcut)  \(item.name)") }
                }
                HStack(spacing: ShotzUI.Space.s) {
                    Button(String(localized: "Open Keyboard Settings")) { Permissions.openKeyboardSettings() }
                        .buttonStyle(.shotz(.secondary, size: .regular))
                    Button(String(localized: "Check Again")) { model.refreshShortcuts() }
                        .buttonStyle(.shotz(.secondary, size: .regular))
                }
            }
            if !model.hotkeys.hotkeysEnabled && !presentsAsNormalRun {
                ShotzBanner(String(localized: "Test run (--no-hotkeys): no shortcuts are registered this run."), tone: .info)
            }
            ForEach(model.heldByAnotherApp, id: \.self) { action in
                if let warning = model.hotkeys.registrationWarning(for: action) {
                    ShotzBanner("\(action.title): \(warning)", tone: .warning)
                }
            }
            if model.canOfferAlternates {
                Button(HotkeyBindings.alternatesTitle(for: model.settings.variant)) { model.useAlternateShortcuts() }
                    .buttonStyle(.shotz(.secondary, size: .regular))
            }
            Note(String(localized: "If a shortcut does nothing, another app may be using it: macOS does not always tell ShotZ."))
        }
    }
}

struct LaunchAtLoginPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var loginItem: LoginItemController
    @Environment(\.presentsAsNormalRun) private var presentsAsNormalRun
    private var name: String { AppVariant.current.displayName }

    var body: some View {
        VStack(alignment: .leading, spacing: ShotzUI.Space.l) {
            LaunchAtLoginIllustration(on: model.launchAtLogin)
            PageText(
                title: String(localized: "Ready when you are"),
                message: String(localized: "Start \(name) when you log in, so your shortcuts always work.")
            )
            Toggle(String(localized: "Launch \(name) at login"), isOn: $model.launchAtLogin)
                .toggleStyle(.shotzSwitch)
                .font(ShotzUI.Typography.body.swiftUIFont)
            Note(loginItem.isInstalled || presentsAsNormalRun
                 ? String(localized: "You can change any of this later in Settings.")
                 : String(localized: "This copy doesn't add itself to your login items (it isn't in Applications, or it is a test run). The choice is saved."))
        }
    }
}
