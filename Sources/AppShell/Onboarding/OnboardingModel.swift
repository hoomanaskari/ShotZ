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
    /// This Mac ran an earlier ShotZ identity (`app.shotz.Shotz`) and its data was migrated.
    let previousIdentityMigrated: Bool
    var onFinish: (() -> Void)?

    init(settings: SettingsStore, hotkeys: HotkeyCenter, loginItem: LoginItemController, screenRecording: ScreenRecordingStatus,
         previousIdentityMigrated: Bool = LegacyDataMigration.forVariant(.current).hasMigrated) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.loginItem = loginItem
        self.screenRecording = screenRecording
        self.previousIdentityMigrated = previousIdentityMigrated
        // First run: the preference default (on). Later: what is really set.
        launchAtLogin = settings.hasCompletedOnboarding ? loginItem.isOn : settings.launchAtLogin
    }

    /// The Screen Recording step explains look-alike entries in System Settings: only after
    /// the identity change on this Mac, and only while permission is missing.
    func showsDuplicateEntryNote(granted: Bool) -> Bool { previousIdentityMigrated && !granted }

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

    /// Capture shortcuts Shotz failed to register this session (another app
    /// may hold them).
    var heldByAnotherApp: [HotkeyAction] {
        [.captureFullscreen, .captureArea, .captureAllInOne].filter { hotkeys.registrationFailures[$0] != nil }
    }

    /// Alternates are offered only where they would take effect (standard profile).
    var canOfferAlternates: Bool { hotkeys.hotkeysEnabled && !heldByAnotherApp.isEmpty }

    func useAlternateShortcuts() {
        for (action, combo) in HotkeyBindings.alternates(for: settings.variant) {
            settings.setHotkey(combo, for: action)
        }
    }

    /// Window closed (Done or the close button): never nag again on launch.
    func finish() {
        // Test runs (--no-hotkeys) never write onboarding or login-item state.
        guard hotkeys.hotkeysEnabled else { return }
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
