import os
import Combine
import Foundation

/// Typed, observable settings over `UserDefaults`. Keys live in ShotzCore so
/// every module reads the same values; the Settings UI lives in AppShell.
///
/// Pass a suite (`UserDefaults(suiteName:)`) in tests. The default is
/// `DevProfile.defaults`: the dev suite in the dev profile, else `.standard`.
@MainActor public final class SettingsStore: ObservableObject {
    public let defaults: UserDefaults

    public init(defaults: UserDefaults = DevProfile.defaults) {
        self.defaults = defaults
    }

    /// The allowed auto-close values in seconds; 0 = off.
    public static let autoCloseChoices = [0, 5, 10, 30]

    // MARK: General

    public var launchAtLogin: Bool {
        get { bool(SettingsKey.launchAtLogin, default: true) }
        set { set(newValue, SettingsKey.launchAtLogin) }
    }
    public var showMenuBarIcon: Bool {
        get { bool(SettingsKey.showMenuBarIcon, default: true) }
        set { set(newValue, SettingsKey.showMenuBarIcon) }
    }
    public var playSounds: Bool {
        get { bool(SettingsKey.playSounds, default: true) }
        set { set(newValue, SettingsKey.playSounds) }
    }
    public var exportFolder: URL {
        get {
            guard let path = defaults.string(forKey: SettingsKey.exportFolder), !path.isEmpty else {
                return ShotzPaths.defaultExportFolder
            }
            return URL(filePath: path, directoryHint: .isDirectory)
        }
        set { set(newValue.path(percentEncoded: false), SettingsKey.exportFolder) }
    }
    public var afterCaptureShowQuickAccess: Bool {
        get { bool(SettingsKey.afterCaptureShowQuickAccess, default: true) }
        set { set(newValue, SettingsKey.afterCaptureShowQuickAccess) }
    }
    public var afterCaptureCopyToClipboard: Bool {
        get { bool(SettingsKey.afterCaptureCopyToClipboard, default: false) }
        set { set(newValue, SettingsKey.afterCaptureCopyToClipboard) }
    }
    public var afterCaptureSave: Bool {
        get { bool(SettingsKey.afterCaptureSave, default: false) }
        set { set(newValue, SettingsKey.afterCaptureSave) }
    }
    public var hasCompletedOnboarding: Bool {
        get { bool(SettingsKey.hasCompletedOnboarding, default: false) }
        set { set(newValue, SettingsKey.hasCompletedOnboarding) }
    }

    // MARK: Shortcuts

    /// Default binding per action (nil = unbound by default).
    public static func defaultHotkey(for action: HotkeyAction) -> KeyCombo? {
        switch action {
        case .captureFullscreen: .defaultFullscreen
        case .captureArea: .defaultArea
        case .captureAllInOne: .defaultAllInOne
        case .captureWindow, .restoreLastClosed: nil
        }
    }

    /// Stored binding; falls back to the default when never set. A cleared
    /// binding is stored explicitly and returns nil.
    public func hotkey(for action: HotkeyAction) -> KeyCombo? {
        let key = SettingsKey.hotkey(action)
        guard let data = defaults.data(forKey: key) else { return Self.defaultHotkey(for: action) }
        do {
            return try JSONDecoder().decode(KeyCombo?.self, from: data)
        } catch {
            ShotzLog.logger("Settings").error("Bad hotkey data for \(key, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Self.defaultHotkey(for: action)
        }
    }

    /// Sets (or clears, with nil) a binding.
    public func setHotkey(_ combo: KeyCombo?, for action: HotkeyAction) {
        do {
            let data = try JSONEncoder().encode(combo)
            set(data, SettingsKey.hotkey(action))
        } catch {
            ShotzLog.logger("Settings").error("Encoding hotkey failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    public func resetHotkeys() {
        objectWillChange.send()
        for action in HotkeyAction.allCases {
            defaults.removeObject(forKey: SettingsKey.hotkey(action))
        }
    }

    // MARK: Quick access

    public var quickAccessSide: StackSide {
        get { enumValue(SettingsKey.quickAccessSide, default: .left) }
        set { set(newValue.rawValue, SettingsKey.quickAccessSide) }
    }
    public var quickAccessDisplay: StackDisplay {
        get { enumValue(SettingsKey.quickAccessDisplay, default: .whereCaptured) }
        set { set(newValue.rawValue, SettingsKey.quickAccessDisplay) }
    }
    public var quickAccessSize: CardSize {
        get { enumValue(SettingsKey.quickAccessSize, default: .large) }
        set { set(newValue.rawValue, SettingsKey.quickAccessSize) }
    }
    /// 0 = off. One of `autoCloseChoices`.
    public var quickAccessAutoCloseSeconds: Int {
        get { defaults.object(forKey: SettingsKey.quickAccessAutoCloseSeconds) as? Int ?? 0 }
        set { set(newValue, SettingsKey.quickAccessAutoCloseSeconds) }
    }
    public var quickAccessRemoveAfterDrag: Bool {
        get { bool(SettingsKey.quickAccessRemoveAfterDrag, default: true) }
        set { set(newValue, SettingsKey.quickAccessRemoveAfterDrag) }
    }
    public var quickAccessCloseAfterCopy: Bool {
        get { bool(SettingsKey.quickAccessCloseAfterCopy, default: false) }
        set { set(newValue, SettingsKey.quickAccessCloseAfterCopy) }
    }
    public var quickAccessCloseAfterSave: Bool {
        get { bool(SettingsKey.quickAccessCloseAfterSave, default: true) }
        set { set(newValue, SettingsKey.quickAccessCloseAfterSave) }
    }
    public var askDestinationWhenSaving: Bool {
        get { bool(SettingsKey.askDestinationWhenSaving, default: false) }
        set { set(newValue, SettingsKey.askDestinationWhenSaving) }
    }

    // MARK: Capture

    public var exportFormat: ImageFormat {
        get { enumValue(SettingsKey.exportFormat, default: .png) }
        set { set(newValue.rawValue, SettingsKey.exportFormat) }
    }
    public var retinaScale: RetinaScale {
        get { enumValue(SettingsKey.retinaScale, default: .native) }
        set { set(newValue.rawValue, SettingsKey.retinaScale) }
    }
    public var windowShadow: Bool {
        get { bool(SettingsKey.windowShadow, default: true) }
        set { set(newValue, SettingsKey.windowShadow) }
    }
    public var fileNamePattern: String {
        get { defaults.string(forKey: SettingsKey.fileNamePattern) ?? FileNaming.defaultPattern }
        set { set(newValue, SettingsKey.fileNamePattern) }
    }

    // MARK: Editor

    public var editorReturnToSelect: Bool {
        get { bool(SettingsKey.editorReturnToSelect, default: false) }
        set { set(newValue, SettingsKey.editorReturnToSelect) }
    }
    public var editorSnapping: Bool {
        get { bool(SettingsKey.editorSnapping, default: true) }
        set { set(newValue, SettingsKey.editorSnapping) }
    }
    public var editorCloseAfterCopy: Bool {
        get { bool(SettingsKey.editorCloseAfterCopy, default: false) }
        set { set(newValue, SettingsKey.editorCloseAfterCopy) }
    }
    public var editorCloseAfterSave: Bool {
        get { bool(SettingsKey.editorCloseAfterSave, default: false) }
        set { set(newValue, SettingsKey.editorCloseAfterSave) }
    }

    // MARK: Advanced

    public var historyRetention: HistoryRetention {
        get { enumValue(SettingsKey.historyRetention, default: .month) }
        set { set(newValue.rawValue, SettingsKey.historyRetention) }
    }

    // MARK: Derived

    /// Capture options built from the current settings.
    public func captureOptions(paths: ShotzPaths = .default) -> CaptureOptions {
        CaptureOptions(
            includeWindowShadow: windowShadow,
            playSound: playSounds,
            destinationDirectory: paths.captures,
            fileNamePattern: fileNamePattern
        )
    }

    /// Removes every Shotz key, restoring all defaults.
    public func resetAll() {
        objectWillChange.send()
        for key in Self.allKeys {
            defaults.removeObject(forKey: key)
        }
    }

    public static var allKeys: [String] {
        [
            SettingsKey.launchAtLogin, SettingsKey.showMenuBarIcon, SettingsKey.playSounds,
            SettingsKey.exportFolder, SettingsKey.afterCaptureShowQuickAccess,
            SettingsKey.afterCaptureCopyToClipboard, SettingsKey.afterCaptureSave,
            SettingsKey.hasCompletedOnboarding,
            SettingsKey.quickAccessSide, SettingsKey.quickAccessDisplay, SettingsKey.quickAccessSize,
            SettingsKey.quickAccessAutoCloseSeconds, SettingsKey.quickAccessRemoveAfterDrag,
            SettingsKey.quickAccessCloseAfterCopy, SettingsKey.quickAccessCloseAfterSave,
            SettingsKey.askDestinationWhenSaving,
            SettingsKey.exportFormat, SettingsKey.retinaScale, SettingsKey.windowShadow,
            SettingsKey.fileNamePattern,
            SettingsKey.editorReturnToSelect, SettingsKey.editorSnapping,
            SettingsKey.editorCloseAfterCopy, SettingsKey.editorCloseAfterSave,
            SettingsKey.historyRetention,
        ] + HotkeyAction.allCases.map(SettingsKey.hotkey)
    }

    // MARK: Helpers

    private func bool(_ key: String, default value: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? value
    }

    private func enumValue<E: RawRepresentable>(_ key: String, default value: E) -> E where E.RawValue == String {
        guard let raw = defaults.string(forKey: key) else { return value }
        return E(rawValue: raw) ?? value
    }

    private func set(_ value: any Sendable, _ key: String) {
        objectWillChange.send()
        defaults.set(value, forKey: key)
    }
}
