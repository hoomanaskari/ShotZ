import Foundation
import Testing
@testable import ShotzCore

struct DevProfileTests {
    let exe = "/x/Shotz.app/Contents/MacOS/Shotz"

    @Test func detection() {
        func active(_ args: [String], _ env: [String: String] = [:]) -> Bool {
            DevProfile.isRequested(arguments: [exe] + args, environment: env)
        }
        #expect(!active([]))
        #expect(!active(["--dev-hotkeys"]))                 // hotkeys alone do not switch profile
        #expect(!active(["-quickAccess.side", "right"]))   // plain argument-domain override
        #expect(active(["--dev-profile"]))
        #expect(active(["--dev-hotkeys", "--debug-present", "/a.png"]))
        #expect(active(["--debug-edit", "/a.png"]))
        #expect(active(["--debug-snapshot-ui", "/tmp/x"]))
        #expect(active(["-QuickAccessSelfTest", "/tmp/r.json"]))
        #expect(active([], ["SHOTZ_DEV_PROFILE": "1"]))
        #expect(!active([], ["SHOTZ_DEV_PROFILE": "0"]))
        #expect(active([], ["SHOTZ_EDITOR_SCRIPT": "/tmp/s.json"]))
        // argv[0] never counts, even if a path happened to look like a flag.
        #expect(!DevProfile.isRequested(arguments: ["--dev-profile"], environment: [:]))
    }

    @Test func defaultsSelection() {
        #expect(DevProfile.makeDefaults(active: false) === UserDefaults.standard)
        let dev = DevProfile.makeDefaults(active: true)
        #expect(dev !== UserDefaults.standard)
        #expect(DevProfile.suiteName == "app.shotz.Shotz.dev")
    }

    @Test func pathsSelection() {
        let standard = ShotzPaths.forProfile(dev: false)
        let dev = ShotzPaths.forProfile(dev: true)
        #expect(standard.root.lastPathComponent == "Shotz")
        #expect(dev.root.lastPathComponent == "Shotz-Dev")
        #expect(dev.root.deletingLastPathComponent() == standard.root.deletingLastPathComponent())
        #expect(standard.temporary.lastPathComponent == "Shotz")
        #expect(dev.temporary.lastPathComponent == "Shotz-Dev")
        #expect(dev.dragExports.path(percentEncoded: false).contains("/Shotz-Dev/"))
        #expect(dev.captures.path(percentEncoded: false).contains("/Shotz-Dev/Captures"))
        // The test process itself is not a dev launch.
        #expect(ShotzPaths.default == ShotzPaths.forProfile(dev: DevProfile.isActive))
    }

    /// A store on the dev suite writes there and never into the real
    /// `app.shotz.Shotz` domain (only read here, never written).
    @MainActor @Test func devWritesLeaveStandardDomainUntouched() {
        let key = "test.devProfile.\(UUID().uuidString)"
        let realDomain = "app.shotz.Shotz" as CFString
        let before = CFPreferencesCopyAppValue(SettingsKey.playSounds as CFString, realDomain)

        let dev = DevProfile.makeDefaults(active: true)
        defer {
            dev.removeObject(forKey: key)
            dev.removeObject(forKey: SettingsKey.fileNamePattern)
        }
        dev.set("x", forKey: key)
        let store = SettingsStore(defaults: dev)
        store.fileNamePattern = "Dev %H"

        #expect(dev.string(forKey: key) == "x")
        #expect(store.fileNamePattern == "Dev %H")
        #expect(CFPreferencesCopyAppValue(key as CFString, realDomain) == nil)
        #expect(UserDefaults.standard.string(forKey: key) == nil)
        let after = CFPreferencesCopyAppValue(SettingsKey.playSounds as CFString, realDomain)
        #expect(String(describing: before) == String(describing: after))
        // Settings written through the dev store are not in the real domain.
        let realPattern = CFPreferencesCopyAppValue(SettingsKey.fileNamePattern as CFString, realDomain) as? String
        #expect(realPattern != "Dev %H")
    }
}
