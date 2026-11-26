import ShotzCore

/// Everything the Settings window needs besides the store itself. Built by
/// `AppCoordinator`, which owns the concrete objects.
@MainActor public struct SettingsContext {
    public let settings: SettingsStore
    public let hotkeys: HotkeyCenter
    public let loginItem: LoginItemController
    public let screenRecording: ScreenRecordingStatus
    /// Removes every capture from history (files included).
    public let clearHistory: () async -> Void
    /// Opens onboarding (optionally at the Screen Recording step).
    public let showOnboarding: (_ permissionStep: Bool) -> Void

    public init(
        settings: SettingsStore,
        hotkeys: HotkeyCenter,
        loginItem: LoginItemController,
        screenRecording: ScreenRecordingStatus,
        clearHistory: @escaping () async -> Void,
        showOnboarding: @escaping (_ permissionStep: Bool) -> Void
    ) {
        self.settings = settings
        self.hotkeys = hotkeys
        self.loginItem = loginItem
        self.screenRecording = screenRecording
        self.clearHistory = clearHistory
        self.showOnboarding = showOnboarding
    }
}

/// Settings tabs (SPEC §7).
public enum SettingsTab: String, CaseIterable, Sendable {
    case general, shortcuts, quickAccess, capture, editor, advanced
}

extension ImageFormat {
    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }
}

extension RetinaScale {
    var title: String {
        switch self {
        case .native: String(localized: "Native")
        case .downscaleTo1x: String(localized: "Downscale to 1×")
        }
    }
}

extension StackSide {
    var title: String {
        switch self {
        case .left: String(localized: "Left")
        case .right: String(localized: "Right")
        }
    }
}

extension StackDisplay {
    var title: String {
        switch self {
        case .whereCaptured: String(localized: "Where captured")
        case .main: String(localized: "Main display")
        }
    }
}

extension CardSize {
    var title: String {
        switch self {
        case .small: String(localized: "Small")
        case .medium: String(localized: "Medium")
        case .large: String(localized: "Large")
        }
    }
}

extension HistoryRetention {
    var title: String {
        switch self {
        case .day: String(localized: "1 day")
        case .week: String(localized: "1 week")
        case .month: String(localized: "1 month")
        case .forever: String(localized: "Forever")
        }
    }
}
