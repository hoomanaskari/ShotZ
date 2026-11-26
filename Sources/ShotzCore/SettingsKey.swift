/// All `UserDefaults` keys Shotz uses. Keep in sync with SPEC §7.
public enum SettingsKey {
    // General
    public static let launchAtLogin = "general.launchAtLogin"
    public static let showMenuBarIcon = "general.showMenuBarIcon"
    public static let playSounds = "general.playSounds"
    public static let exportFolder = "general.exportFolder"
    public static let afterCaptureShowQuickAccess = "general.afterCapture.showQuickAccess"
    public static let afterCaptureCopyToClipboard = "general.afterCapture.copyToClipboard"
    public static let afterCaptureSave = "general.afterCapture.save"
    public static let hasCompletedOnboarding = "general.hasCompletedOnboarding"

    // Shortcuts
    public static func hotkey(_ action: HotkeyAction) -> String { "shortcuts.\(action.rawValue)" }

    // Quick access
    public static let quickAccessSide = "quickAccess.side"
    public static let quickAccessDisplay = "quickAccess.display"
    public static let quickAccessSize = "quickAccess.size"
    public static let quickAccessAutoCloseSeconds = "quickAccess.autoCloseSeconds"
    public static let quickAccessRemoveAfterDrag = "quickAccess.removeAfterDrag"
    public static let quickAccessCloseAfterCopy = "quickAccess.closeAfterCopy"
    public static let quickAccessCloseAfterSave = "quickAccess.closeAfterSave"
    public static let askDestinationWhenSaving = "quickAccess.askDestination"

    // Capture
    public static let exportFormat = "capture.format"
    public static let retinaScale = "capture.retinaScale"
    public static let windowShadow = "capture.windowShadow"
    public static let fileNamePattern = "capture.fileNamePattern"

    // Editor
    public static let editorReturnToSelect = "editor.returnToSelect"
    public static let editorSnapping = "editor.snapping"
    public static let editorCloseAfterCopy = "editor.closeAfterCopy"
    public static let editorCloseAfterSave = "editor.closeAfterSave"

    // Advanced
    public static let historyRetention = "advanced.historyRetention"
}
