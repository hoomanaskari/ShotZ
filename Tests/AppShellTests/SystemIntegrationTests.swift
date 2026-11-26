import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

struct SymbolicHotKeyTests {
    func allOff() -> [String: Any] {
        Dictionary(uniqueKeysWithValues: SystemScreenshotShortcuts.ids.map {
            (String($0), ["enabled": false, "value": ["type": "standard"]] as [String: Any])
        })
    }

    @Test func idsAreTheScreenshotOnes() {
        #expect(SystemScreenshotShortcuts.ids == [28, 29, 30, 31, 184])
    }

    @Test func allDisabled() {
        let s = SystemScreenshotShortcuts.parse(allOff())
        #expect(!s.anyEnabled)
        #expect(s.enabledItems.isEmpty)
        #expect(s.items.count == 5)
    }

    @Test func oneEnabledIsReported() {
        var d = allOff()
        d["30"] = ["enabled": true]
        let s = SystemScreenshotShortcuts.parse(d)
        #expect(s.anyEnabled)
        #expect(s.enabledItems.map(\.id) == [30])
        #expect(s.enabledItems.first?.shortcut == "⇧⌘4")
    }

    @Test func missingEntryOrDictionaryMeansSystemDefaultOn() {
        var d = allOff()
        d["184"] = nil
        #expect(SystemScreenshotShortcuts.parse(d).enabledItems.map(\.id) == [184])
        #expect(SystemScreenshotShortcuts.parse(nil).enabledItems.count == 5)
        #expect(SystemScreenshotShortcuts.parse([:]).enabledItems.count == 5)
    }

    @Test func numericAndStringFlags() {
        var d = allOff()
        d["28"] = ["enabled": NSNumber(value: 1)]
        d["29"] = ["enabled": NSNumber(value: 0)]
        d["31"] = ["enabled": "0"]
        d["184"] = ["value": [:] as [String: Any]]   // no flag → default on
        #expect(SystemScreenshotShortcuts.parse(d).enabledItems.map(\.id) == [28, 184])
    }

    @Test func unrelatedIdsIgnored() {
        var d = allOff()
        d["32"] = ["enabled": true]
        d["64"] = ["enabled": true]
        #expect(!SystemScreenshotShortcuts.parse(d).anyEnabled)
    }

    @Test func readingTheRealDomainDoesNotCrash() {
        // Read-only; the value depends on the machine.
        #expect(SystemScreenshotShortcuts.read().items.count == 5)
    }
}

struct LoginItemTests {
    let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    @Test func installedLocations() {
        #expect(LoginItemController.isInstalledLocation(URL(filePath: "/Applications/Shotz.app"), home: home))
        #expect(LoginItemController.isInstalledLocation(URL(filePath: "/Applications/Utilities/Shotz.app"), home: home))
        #expect(LoginItemController.isInstalledLocation(URL(filePath: "/Users/someone/Applications/Shotz.app"), home: home))
    }

    @Test func devBundlesAreNotInstalled() {
        #expect(!LoginItemController.isInstalledLocation(URL(filePath: "/Users/someone/Sites/shotz/build/Shotz.app"), home: home))
        #expect(!LoginItemController.isInstalledLocation(URL(filePath: "/Users/someone/ApplicationsX/Shotz.app"), home: home))
        #expect(!LoginItemController.isInstalledLocation(URL(filePath: "/ApplicationsCopy/Shotz.app"), home: home))
        #expect(!LoginItemController.isInstalledLocation(URL(filePath: "/Users/someone/Applications/../Sites/Shotz.app"), home: home))
    }

    /// First launch from /Applications after onboarding in a dev build: the
    /// stored "on" is applied, never overwritten with "not registered".
    @Test func launchActionMatrix() {
        func act(_ pref: Bool, _ state: LoginItemController.State, installed: Bool = true, onboarded: Bool = true)
            -> LoginItemController.LaunchAction {
            LoginItemController.launchAction(preference: pref, state: state, installed: installed, onboarded: onboarded)
        }
        #expect(act(true, .disabled) == .register)
        #expect(act(false, .disabled) == .none)
        #expect(act(true, .enabled) == .none)
        #expect(act(false, .enabled) == .mirrorOn)
        #expect(act(true, .requiresApproval) == .none)      // user turned it off in Login Items
        #expect(act(true, .failed("x")) == .none)
        #expect(act(true, .disabled, installed: false) == .none)   // dev bundle never registers
        #expect(act(true, .disabled, onboarded: false) == .none)   // onboarding asks first
        #expect(act(true, .notInstalled) == .none)
    }

    @Test func registrationPolicyPerVariant() {
        let build = URL(filePath: "/Users/someone/Sites/shotz/build/Shotz Dev.app")
        let apps = URL(filePath: "/Applications/Shotz.app")
        #expect(LoginItemController.registrationAllowed(variant: .production, bundleURL: apps, testRun: false))
        #expect(!LoginItemController.registrationAllowed(variant: .production, bundleURL: build, testRun: false))
        #expect(LoginItemController.registrationAllowed(variant: .development, bundleURL: build, testRun: false))
        #expect(!LoginItemController.registrationAllowed(variant: .development, bundleURL: build, testRun: true))
        #expect(!LoginItemController.registrationAllowed(variant: .production, bundleURL: apps, testRun: true))
    }

    @MainActor @Test func devBundleNeverRegistersButStoresPreference() throws {
        let (settings, _) = makeSettings()
        let item = LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/Shotz.app"), variant: .production)
        #expect(item.state == .notInstalled)
        item.setEnabled(false)
        #expect(settings.launchAtLogin == false)
        #expect(item.state == .notInstalled)
        #expect(item.isOn == false)
        item.setEnabled(true)
        #expect(item.isOn == true)
    }
}

struct RelaunchTests {
    @Test func keepsOnlyNoHotkeys() {
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--no-hotkeys", "--debug-present", "/a.png"]) == ["--no-hotkeys"])
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--debug-edit", "/a.png"]).isEmpty)
    }
}

@MainActor
func makeSettings() -> (SettingsStore, String) {
    let suite = "ShotzAppShellTests-\(UUID().uuidString)"
    return (SettingsStore(defaults: MemoryDefaults()), suite)
}
