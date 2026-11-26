import ShotzCore

/// What happens after a capture lands (SPEC §3.5, §7 General), read from
/// settings at the moment of the capture.
public struct AfterCaptureActions: Equatable, Sendable {
    public var showQuickAccess: Bool
    public var copyToClipboard: Bool
    public var saveToExportFolder: Bool

    public init(showQuickAccess: Bool, copyToClipboard: Bool, saveToExportFolder: Bool) {
        self.showQuickAccess = showQuickAccess
        self.copyToClipboard = copyToClipboard
        self.saveToExportFolder = saveToExportFolder
    }

    @MainActor public init(settings: SettingsStore) {
        self.init(
            showQuickAccess: settings.afterCaptureShowQuickAccess,
            copyToClipboard: settings.afterCaptureCopyToClipboard,
            saveToExportFolder: settings.afterCaptureSave
        )
    }

    /// True when the capture would otherwise vanish silently (no card, no
    /// copy, no save); it still goes to history and the status menu.
    public var isSilent: Bool { !showQuickAccess && !copyToClipboard && !saveToExportFolder }
}
