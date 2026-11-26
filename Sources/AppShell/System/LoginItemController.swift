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
    /// Whether this copy may register a login item (see `registrationAllowed`).
    /// `notInstalled` covers both "not in Applications" and "test run".
    public let isInstalled: Bool
    public let variant: AppVariant
    private let settings: SettingsStore
    private let log = ShotzLog.logger("AppShell")

    public init(
        settings: SettingsStore,
        bundleURL: URL = Bundle.main.bundleURL,
        variant: AppVariant = .current,
        testRun: Bool = false
    ) {
        self.settings = settings
        self.variant = variant
        self.isInstalled = Self.registrationAllowed(variant: variant, bundleURL: bundleURL, testRun: testRun)
        refresh()
    }

    /// Production registers only from Applications (a build folder copy never
    /// adds itself). Shotz Dev has its own login item, so it may register from
    /// wherever it runs, except in engineer/test runs (`--no-hotkeys`).
    public nonisolated static func registrationAllowed(variant: AppVariant, bundleURL: URL, testRun: Bool) -> Bool {
        if testRun { return false }
        switch variant {
        case .production: return isInstalledLocation(bundleURL)
        case .development: return true
        }
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
            log.error("Launch at login change failed: \(error.localizedDescription, privacy: .private)")
        }
    }

    /// What to do at launch, given the stored choice and the system state.
    enum LaunchAction: Equatable {
        case none
        /// The choice is "on" but nothing is registered yet (typically the
        /// first launch from /Applications after onboarding ran in a dev
        /// build): register now.
        case register
        /// Registered in the system although the choice says "off": show "on".
        case mirrorOn
    }

    nonisolated static func launchAction(preference: Bool, state: State, installed: Bool, onboarded: Bool) -> LaunchAction {
        guard installed, onboarded else { return .none }
        switch state {
        case .disabled: return preference ? .register : .none
        // Turned off by the user in System Settings ▸ Login Items shows as
        // requiresApproval: never fight that, the UI explains it.
        case .enabled, .requiresApproval: return preference ? .none : .mirrorOn
        case .notInstalled, .failed: return .none
        }
    }

    /// At launch from an installed location, after onboarding: apply the
    /// stored choice instead of overwriting it with "not registered".
    public func applyAtLaunch() {
        refresh()
        switch Self.launchAction(preference: settings.launchAtLogin, state: state,
                                 installed: isInstalled, onboarded: settings.hasCompletedOnboarding) {
        case .none: break
        case .register:
            log.info("Launch at login: registering the stored choice")
            setEnabled(true)
        case .mirrorOn:
            settings.launchAtLogin = true
        }
    }

    public func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
