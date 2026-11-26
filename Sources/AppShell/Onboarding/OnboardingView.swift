import AppKit
import ShotzCore
import SwiftUI

struct OnboardingView: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch model.step {
                case .welcome: WelcomePage(model: model)
                case .screenRecording: ScreenRecordingPage(model: model, status: model.screenRecording)
                case .systemShortcuts: SystemShortcutsPage(model: model)
                case .launchAtLogin: LaunchAtLoginPage(model: model, loginItem: model.loginItem)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 36)

            Divider()
            HStack {
                StepDots(current: model.step)
                Spacer()
                if !model.isFirst {
                    Button(String(localized: "Back")) { model.back() }
                        .keyboardShortcut(.cancelAction)
                }
                Button(model.isLast ? String(localized: "Done") : String(localized: "Continue")) { model.next() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 600, height: 470)
    }
}

private struct StepDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases, id: \.self) { step in
                Capsule()
                    .fill(step == current ? Color.accentColor : Color.secondary.opacity(0.3))
                    .frame(width: step == current ? 18 : 7, height: 7)
            }
        }
        .animation(.snappy, value: current)
        .accessibilityElement()
        .accessibilityLabel(String(localized: "Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)"))
    }
}

/// Large symbol + title + body used at the top of every page.
struct PageHeader: View {
    let symbol: String?
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.system(size: 40, weight: .regular))
                    .foregroundStyle(Color.accentColor)
                    .frame(height: 48)
            } else {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: 80, height: 80)
            }
            Text(title).font(.title2.weight(.semibold))
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WelcomePage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(
                symbol: nil,
                title: String(localized: "Welcome to Shotz"),
                message: String(localized: "Take a screenshot, find it waiting in the corner of your screen, mark it up, and drop it wherever it needs to go.")
            )
            VStack(alignment: .leading, spacing: 8) {
                ForEach([HotkeyAction.captureArea, .captureFullscreen, .captureAllInOne], id: \.self) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(model.hotkeys.binding(for: action).map(KeyNames.display) ?? String(localized: "No shortcut"))
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            .frame(maxWidth: 360)
            Text(model.settings.showMenuBarIcon
                 ? String(localized: "Shotz lives in the menu bar. Everything else is a shortcut away.")
                 : String(localized: "The menu-bar icon is hidden. Open Shotz again from Finder or Spotlight to reach Settings."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

struct ScreenRecordingPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var status: ScreenRecordingStatus

    var body: some View {
        VStack(spacing: 20) {
            PageHeader(
                symbol: "rectangle.dashed.badge.record",
                title: model.reason == .permissionMissing
                    ? String(localized: "Shotz needs Screen Recording")
                    : String(localized: "Allow Screen Recording"),
                message: String(localized: "macOS only lets apps see what's on screen with your permission. Shotz uses it for screenshots and nothing else: no recording, no network.")
            )
            HStack(spacing: 8) {
                Image(systemName: status.isGranted ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(status.isGranted ? .green : .orange)
                    .font(.title3)
                Text(status.isGranted
                     ? String(localized: "Screen Recording is allowed")
                     : String(localized: "Not allowed yet"))
                    .font(.headline)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background((status.isGranted ? Color.green : Color.orange).opacity(0.12), in: Capsule())
            .accessibilityElement(children: .combine)

            if !status.isGranted {
                Button(String(localized: "Open System Settings")) {
                    // Makes Shotz appear in the list (first time only), then
                    // opens Privacy & Security ▸ Screen & System Audio Recording.
                    Permissions.requestScreenRecording()
                    Permissions.openScreenRecordingSettings()
                }
                .controlSize(.large)
                Text(String(localized: "Turn on Shotz in the list. If macOS asks to quit and reopen Shotz, choose Later and use Relaunch below."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Relaunch Shotz")) { Permissions.relaunch() }
                .buttonStyle(.link)
        }
    }
}

struct SystemShortcutsPage: View {
    @ObservedObject var model: OnboardingModel

    var body: some View {
        let shortcuts = model.systemShortcuts
        VStack(spacing: 16) {
            PageHeader(
                symbol: "keyboard",
                title: String(localized: "Screenshot shortcuts"),
                message: shortcuts.anyEnabled
                    ? String(localized: "macOS's own screenshot shortcuts are on, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 won't reach Shotz yet.")
                    : String(localized: "macOS's own screenshot shortcuts are off, so ⇧⌘3, ⇧⌘4 and ⇧⌘5 can reach Shotz.")
            )
            if shortcuts.anyEnabled {
                VStack(alignment: .leading, spacing: 6) {
                    Text(String(localized: "To turn them off:")).font(.headline)
                    Text(String(localized: "1. Open System Settings ▸ Keyboard and click Keyboard Shortcuts…"))
                    Text(String(localized: "2. Choose Screenshots in the sidebar."))
                    Text(String(localized: "3. Untick these:"))
                    ForEach(shortcuts.enabledItems) { item in
                        Text("    \(item.shortcut)  \(item.name)").foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                HStack {
                    Button(String(localized: "Open Keyboard Settings")) { Permissions.openKeyboardSettings() }
                    Button(String(localized: "Check Again")) { model.refreshShortcuts() }
                }
            } else {
                Label(String(localized: "Nothing to change"), systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.headline)
            }
            if model.hotkeys.devHotkeys {
                Text(String(localized: "Running with --dev-hotkeys: this session uses ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5."))
                    .font(.callout).foregroundStyle(.secondary)
            } else if !model.heldByAnotherApp.isEmpty {
                VStack(spacing: 8) {
                    Text(String(localized: "Another app is already using \(model.heldByAnotherApp.compactMap { model.hotkeys.binding(for: $0).map(KeyNames.display) }.joined(separator: ", ")). Quit it or turn its shortcuts off, or use alternates."))
                        .font(.callout).multilineTextAlignment(.center)
                    Button(String(localized: "Use ⌃⌥⌘3, ⌃⌥⌘4 and ⌃⌥⌘5")) { model.useAlternateShortcuts() }
                }
            }
        }
    }
}

struct LaunchAtLoginPage: View {
    @ObservedObject var model: OnboardingModel
    @ObservedObject var loginItem: LoginItemController

    var body: some View {
        VStack(spacing: 22) {
            PageHeader(
                symbol: "power",
                title: String(localized: "Ready when you are"),
                message: String(localized: "Start Shotz when you log in, so your shortcuts always work.")
            )
            Toggle(String(localized: "Launch Shotz at login"), isOn: $model.launchAtLogin)
                .toggleStyle(.switch)
            if !loginItem.isInstalled {
                Text(String(localized: "This is a development build, so nothing is added to your login items. The choice is saved for when Shotz runs from Applications."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(String(localized: "You can change any of this later in Settings."))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
