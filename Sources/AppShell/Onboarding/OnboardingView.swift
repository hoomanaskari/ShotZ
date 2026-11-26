import AppKit
import ShotzCore
import SwiftUI

/// The welcome window: a sidebar with the steps (progress), the step's
/// illustration, title, text and actions, and Back / Continue at the bottom.
struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel
    static let size = CGSize(width: 700, height: 500)

    var body: some View {
        HStack(spacing: 0) {
            StepSidebar(current: model.step)
                .frame(width: 214)
            Divider()
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
                .padding(.horizontal, 32)
                .padding(.top, 40)

                HStack {
                    Text(String(localized: "Step \(model.step.rawValue + 1) of \(OnboardingStep.allCases.count)"))
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    if !model.isFirst {
                        Button(String(localized: "Back")) { model.back() }
                            .keyboardShortcut(.cancelAction)
                    }
                    Button(model.isLast ? String(localized: "Done") : String(localized: "Continue")) { model.next() }
                        .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
    }
}

private struct StepSidebar: View {
    let current: OnboardingStep

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 36, height: 36)
                Text(AppVariant.current.displayName)
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.top, 44)
            .padding(.bottom, 28)

            VStack(alignment: .leading, spacing: 4) {
                ForEach(OnboardingStep.allCases, id: \.self) { step in
                    StepRow(step: step, state: step == current ? .current : (step.rawValue < current.rawValue ? .done : .upcoming))
                }
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Color.primary.opacity(0.035))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(String(localized: "Steps"))
    }
}

private struct StepRow: View {
    enum State { case done, current, upcoming }
    let step: OnboardingStep
    let state: State

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(state == .upcoming ? Color.clear : Color.accentColor)
                    .overlay(Circle().strokeBorder(state == .upcoming ? Color.secondary.opacity(0.5) : Color.clear, lineWidth: 1))
                if state == .done {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.white)
                } else {
                    Text("\(step.rawValue + 1)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(state == .current ? Color.white : Color.secondary)
                }
            }
            .frame(width: 20, height: 20)
            Text(step.title)
                .font(.system(size: 13, weight: state == .current ? .semibold : .regular))
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(state == .upcoming ? Color.secondary : Color.primary)
            Spacer()
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 7).fill(state == .current ? Color.accentColor.opacity(0.12) : Color.clear))
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
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 22, weight: .semibold)).accessibilityAddTraits(.isHeader)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
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
        VStack(alignment: .leading, spacing: 20) {
            WelcomeIllustration()
            PageText(
                title: String(localized: "Welcome to \(AppVariant.current.displayName)"),
                message: String(localized: "Take a screenshot, find it waiting in the corner of your screen, mark it up, and drop it wherever it needs to go.")
            )
            VStack(alignment: .leading, spacing: 8) {
                ForEach([HotkeyAction.captureArea, .captureFullscreen, .captureAllInOne], id: \.self) { action in
                    HStack {
                        Text(action.title).font(.system(size: 13))
                        Spacer()
                        // The stored shortcut: what the user gets (even if this run has --no-hotkeys).
                        if let combo = model.settings.hotkey(for: action) {
                            KeyCapsRow(combo: combo, size: 11)
                        } else {
                            Text(String(localized: "No shortcut")).font(.system(size: 12)).foregroundStyle(.secondary)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScreenRecordingIllustration(granted: status.isGranted)
            PageText(
                title: model.reason == .permissionMissing
                    ? String(localized: "\(AppVariant.current.displayName) needs Screen Recording")
                    : String(localized: "Allow Screen Recording"),
                message: String(localized: "macOS only lets apps see what's on screen with your permission. Shotz uses it for screenshots and nothing else: no recording, no network.")
            )
            HStack(spacing: 12) {
                StatusPill(text: status.isGranted ? String(localized: "Screen Recording is allowed") : String(localized: "Not allowed yet"),
                           positive: status.isGranted)
                if !status.isGranted {
                    Button(String(localized: "Open System Settings")) {
                        // Makes Shotz appear in the list (first time only), then
                        // opens Privacy & Security ▸ Screen & System Audio Recording.
                        Permissions.requestScreenRecording()
                        Permissions.openScreenRecordingSettings()
                    }
                }
            }
            Text(status.isGranted
                 ? String(localized: "If captures still fail, relaunch so macOS applies the permission.")
                 : String(localized: "Turn on \(AppVariant.current.displayName) in the list. If macOS asks to quit and reopen it, choose Later, then relaunch here."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button(String(localized: "Relaunch \(AppVariant.current.displayName)")) { Permissions.relaunch() }
                .buttonStyle(.link)
                .font(.system(size: 12))
        }
    }
}

struct SystemShortcutsPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let shortcuts = model.systemShortcuts
        let combos = [HotkeyAction.captureFullscreen, .captureArea, .captureAllInOne].compactMap { model.settings.hotkey(for: $0) }
        VStack(alignment: .leading, spacing: 16) {
            ShortcutsIllustration(combos: combos, allClear: !shortcuts.anyEnabled)
            PageText(
                title: String(localized: "Screenshot shortcuts"),
                message: shortcuts.anyEnabled
                    ? String(localized: "macOS's own screenshot shortcuts are on, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 won't reach Shotz yet.")
                    : String(localized: "macOS's own screenshot shortcuts are off, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 can reach Shotz.")
            )
            if shortcuts.anyEnabled {
                VStack(alignment: .leading, spacing: 4) {
                    Text(String(localized: "System Settings ▸ Keyboard ▸ Keyboard Shortcuts… ▸ Screenshots, untick:"))
                        .font(.system(size: 12, weight: .medium))
                    ForEach(shortcuts.enabledItems) { item in
                        Text("\(item.shortcut)  \(item.name)").font(.system(size: 12)).foregroundStyle(.secondary)
                    }
                }
                HStack {
                    Button(String(localized: "Open Keyboard Settings")) { Permissions.openKeyboardSettings() }
                    Button(String(localized: "Check Again")) { model.refreshShortcuts() }
                }
            }
            if !model.hotkeys.hotkeysEnabled {
                note(String(localized: "Started with --no-hotkeys: no shortcuts are registered this run."))
            }
            ForEach(model.heldByAnotherApp, id: \.self) { action in
                if let warning = model.hotkeys.registrationWarning(for: action) {
                    Label("\(action.title): \(warning)", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(.orange)
                }
            }
            if model.canOfferAlternates {
                Button(HotkeyBindings.alternatesTitle(for: model.settings.variant)) { model.useAlternateShortcuts() }
            }
            note(String(localized: "If a shortcut does nothing, another app may be using it: macOS does not always tell Shotz."))
        }
    }

    private func note(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

struct LaunchAtLoginPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            LaunchAtLoginIllustration(on: model.launchAtLogin)
            PageText(
                title: String(localized: "Ready when you are"),
                message: String(localized: "Start \(AppVariant.current.displayName) when you log in, so your shortcuts always work.")
            )
            Toggle(String(localized: "Launch \(AppVariant.current.displayName) at login"), isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
            Text(loginItem.isInstalled
                 ? String(localized: "You can change any of this later in Settings.")
                 : String(localized: "This copy doesn't add itself to your login items (it isn't in Applications, or it is a test run). The choice is saved."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
