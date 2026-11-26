import os
import Combine
import Foundation
import ServiceManagement
import ShotzCore

/// Launch at login via `SMAppService.mainApp` (SPEC §1, §7).
///
/// The system's state is the truth; the `launchAtLogin` preference mirrors
/// it. A dev bundle (anywhere but /Applications or ~/Applications) is never
/// registered, so a debug build cannot add itself to the user's login items;
/// the preference is still stored and applied once Shotz runs installed.
@MainActor public final class LoginItemController: ObservableObject {
    public enum State: Equatable, Sendable {
        case enabled
        case disabled
        /// Registered, but the user must allow it in System Settings ▸ Login Items.
        case requiresApproval
        /// Running from a build folder; nothing is registered.
        case notInstalled
        case failed(String)
    }

    @Published public private(set) var state: State = .disabled
    public let isInstalled: Bool
    private let settings: SettingsStore
    private let log = ShotzLog.logger("AppShell")

    public init(settings: SettingsStore, bundleURL: URL = Bundle.main.bundleURL) {
        self.settings = settings
        self.isInstalled = Self.isInstalledLocation(bundleURL)
        refresh()
    }

    /// /Applications/… or ~/Applications/… (any depth).
    public nonisolated static func isInstalledLocation(
        _ bundleURL: URL,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> Bool {
        let path = bundleURL.standardizedFileURL.path(percentEncoded: false)
        let userApps = home.appending(path: "Applications", directoryHint: .isDirectory)
            .standardizedFileURL.path(percentEncoded: false)
        return path.hasPrefix("/Applications/") || path.hasPrefix(userApps.hasSuffix("/") ? userApps : userApps + "/")
    }

    public var isOn: Bool {
        switch state {
        case .enabled, .requiresApproval: true
        case .notInstalled: settings.launchAtLogin
        case .disabled, .failed: false
        }
    }

    public func refresh() {
        guard isInstalled else {
            state = .notInstalled
            return
        }
        state = Self.state(for: SMAppService.mainApp.status)
    }

    nonisolated static func state(for status: SMAppService.Status) -> State {
        switch status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered, .notFound: .disabled
        @unknown default: .disabled
        }
    }

    /// User toggled the setting (Settings or onboarding).
    public func setEnabled(_ on: Bool) {
        settings.launchAtLogin = on
        guard isInstalled else {
            log.info("Launch at login stored as \(on) (dev bundle: not registering)")
            state = .notInstalled
            return
        }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            refresh()
            log.info("Launch at login \(on ? "registered" : "unregistered", privacy: .public)")
        } catch {
            refresh()
            if state == (on ? .enabled : .disabled) { return }
            state = .failed(error.localizedDescription)
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// At launch: after onboarding the system state wins (the user may have
    /// removed Shotz in System Settings), so mirror it into the preference.
    public func syncPreferenceFromSystem() {
        refresh()
        guard isInstalled, settings.hasCompletedOnboarding else { return }
        let on = state == .enabled || state == .requiresApproval
        if settings.launchAtLogin != on { settings.launchAtLogin = on }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
