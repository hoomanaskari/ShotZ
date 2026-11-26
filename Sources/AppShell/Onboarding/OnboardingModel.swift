import Combine
import ShotzCore

@MainActor final class OnboardingModel: ObservableObject {
    enum Reason { case welcome, permissionMissing }

    @Published var step: OnboardingStep = .welcome
    @Published var reason: Reason = .welcome
    @Published private(set) var systemShortcuts = SystemScreenshotShortcuts.read()
    /// The launch-at-login choice, applied when onboarding finishes.
    @Published var launchAtLogin: Bool

    let settings: SettingsStore
    let hotkeys: HotkeyCenter
    let loginItem: LoginItemController
    let screenRecording: ScreenRecordingStatus
    var onFinish: (() -> Void)?

    init(settings: SettingsStore, hotkeys: HotkeyCenter, loginItem: LoginItemController, screenRecording: ScreenRecordingStatus) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.loginItem = loginItem
        self.screenRecording = screenRecording
        // First run: the preference default (on). Later: what is really set.
        launchAtLogin = settings.hasCompletedOnboarding ? loginItem.isOn : settings.launchAtLogin
    }

    var isLast: Bool { step == OnboardingStep.allCases.last }
    var isFirst: Bool { step == OnboardingStep.allCases.first }

    func next() {
        if isLast {
            onFinish?()   // closes the window, which calls finish()
        } else if let s = OnboardingStep(rawValue: step.rawValue + 1) {
            step = s
            if s == .systemShortcuts { refreshShortcuts() }
        }
    }

    func back() {
        if let s = OnboardingStep(rawValue: step.rawValue - 1) { step = s }
    }

    func refreshShortcuts() {
        systemShortcuts = SystemScreenshotShortcuts.read()
    }

    /// Capture shortcuts Shotz failed to register (another app holds them).
    var heldByAnotherApp: [HotkeyAction] {
        guard !hotkeys.devHotkeys else { return [] }
        return [.captureFullscreen, .captureArea, .captureAllInOne].filter { hotkeys.registrationFailures[$0] != nil }
    }

    func useAlternateShortcuts() {
        settings.setHotkey(.devFullscreen, for: .captureFullscreen)
        settings.setHotkey(.devArea, for: .captureArea)
        settings.setHotkey(.devAllInOne, for: .captureAllInOne)
    }

    /// Window closed (Done or the close button): never nag again on launch.
    func finish() {
        let firstRun = !settings.hasCompletedOnboarding
        if firstRun || launchAtLogin != loginItem.isOn {
            loginItem.setEnabled(launchAtLogin)
        }
        settings.hasCompletedOnboarding = true
    }

    /// Re-arms after a close so the window can be shown again.
    func reopen() {
        launchAtLogin = settings.hasCompletedOnboarding ? loginItem.isOn : settings.launchAtLogin
    }
}
