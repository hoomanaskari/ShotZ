import Foundation
import Testing
@testable import ShotzCore

struct AppVariantTests {
    @Test func variantFromBundleID() {
        #expect(AppVariant.from(bundleIdentifier: "app.shotz.Shotz") == .production)
        #expect(AppVariant.from(bundleIdentifier: "app.shotz.Shotz.dev") == .development)
        #expect(AppVariant.from(bundleIdentifier: nil) == .production)
        #expect(AppVariant.from(bundleIdentifier: "com.apple.dt.xctest.tool") == .production)
        #expect(AppVariant.current == .production)   // the test runner
    }

    @Test func namesAndIDs() {
        #expect(AppVariant.production.displayName == "ShotZ")
        #expect(AppVariant.development.displayName == "ShotZ Dev")
        #expect(AppVariant.production.dataDirectoryName == "Shotz")      // existing history folder kept
        #expect(AppVariant.development.dataDirectoryName == "ShotZ Dev")
        #expect(AppVariant.development.bundleIdentifier == "app.shotz.Shotz.dev")
        #expect(AppVariant.production.launchAtLoginDefault && !AppVariant.development.launchAtLoginDefault)
    }

    /// Both apps can run at once: their default capture shortcuts never overlap.
    @Test func defaultShortcutsDiffer() {
        let prod = Set(HotkeyAction.allCases.compactMap { AppVariant.production.defaultHotkey(for: $0) })
        let dev = Set(HotkeyAction.allCases.compactMap { AppVariant.development.defaultHotkey(for: $0) })
        #expect(prod == [.defaultFullscreen, .defaultArea, .defaultAllInOne])
        #expect(dev == [.devFullscreen, .devArea, .devAllInOne])
        #expect(prod.isDisjoint(with: dev))
    }

    @Test func dataFoldersAreSeparate() {
        let prod = ShotzPaths.forVariant(.production), dev = ShotzPaths.forVariant(.development)
        #expect(prod.root.lastPathComponent == "Shotz")
        #expect(dev.root.lastPathComponent == "ShotZ Dev")
        #expect(dev.temporary.lastPathComponent == "ShotZ Dev")
        let prodPrefix = prod.root.standardizedFileURL.path(percentEncoded: false)
        for url in [dev.root, dev.captures, dev.documents, dev.historyIndex, dev.temporary, dev.dragExports] {
            #expect(!url.standardizedFileURL.path(percentEncoded: false).hasPrefix(prodPrefix.hasSuffix("/") ? prodPrefix : prodPrefix + "/"))
        }
        #expect(ShotzPaths.default == ShotzPaths.forVariant(.production))
    }

    @MainActor @Test func settingsStoreDefaultsFollowVariant() throws {
        let suite = "ShotzVariantTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let prod = SettingsStore(defaults: defaults, variant: .production)
        let dev = SettingsStore(defaults: defaults, variant: .development)
        #expect(prod.hotkey(for: .captureArea) == .defaultArea)
        #expect(dev.hotkey(for: .captureArea) == .devArea)
        dev.resetHotkeys()
        #expect(dev.hotkey(for: .captureFullscreen) == .devFullscreen)
        #expect(prod.launchAtLogin && !dev.launchAtLogin)
    }

    // MARK: Hermetic test runs

    @Test func testRunDetection() {
        func run(_ args: [String], _ env: [String: String] = [:]) -> Bool {
            AppVariant.isTestRun(arguments: ["/x/ShotZ"] + args, environment: env)
        }
        #expect(!run([]))
        #expect(run(["--no-hotkeys"]))
        #expect(run(["--debug-present", "/a.png"]))
        #expect(run(["-QuickAccessSelfTest", "/tmp/r.json"]))
        #expect(run([], ["SHOTZ_EDITOR_SCRIPT": "/tmp/s.json"]))
        #expect(!run(["-quickAccess.side", "right"]))
        #expect(!AppVariant.isTestRun(arguments: ["--no-hotkeys"], environment: [:]))
        #expect(!AppVariant.isTestRun)   // the unit-test runner itself
    }

    @Test func testRunPreferencesAreASeparateSuite() {
        #expect(AppVariant.development.testRunSuiteName == "app.shotz.Shotz.dev.testrun")
        #expect(AppVariant.production.testRunSuiteName == "app.shotz.Shotz.testrun")
        #expect(AppVariant.preferences(variant: .development, testRun: false) === UserDefaults.standard)
        let suite = AppVariant.preferences(variant: .development, testRun: true)
        #expect(suite !== UserDefaults.standard)
        let key = "test.hermetic.\(UUID().uuidString)"
        defer { suite.removeObject(forKey: key) }
        suite.set(true, forKey: key)
        #expect(UserDefaults.standard.object(forKey: key) == nil)
        #expect(CFPreferencesCopyAppValue(key as CFString, "app.shotz.Shotz.dev" as CFString) == nil)
    }

    @Test func testRunDataFolderIsSeparate() {
        let dev = ShotzPaths.forVariant(.development), devTest = ShotzPaths.forVariant(.development, testRun: true)
        let prodTest = ShotzPaths.forVariant(.production, testRun: true)
        #expect(devTest.root.lastPathComponent == "ShotZ Dev Test Runs")
        #expect(prodTest.root.lastPathComponent == "ShotZ Test Runs")
        #expect(devTest.temporary.lastPathComponent == "ShotZ Dev Test Runs")
        let devPrefix = dev.root.standardizedFileURL.path(percentEncoded: false)
        #expect(!devTest.historyIndex.path(percentEncoded: false).hasPrefix(devPrefix.hasSuffix("/") ? devPrefix : devPrefix + "/"))
        #expect(ShotzPaths.default == ShotzPaths.forVariant(.production, testRun: false))
    }

    @MainActor @Test func oldDefaultFileNamePatternIsMigrated() throws {
        let suite = "ShotzRenameTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        defaults.set(FileNaming.legacyDefaultPattern, forKey: SettingsKey.fileNamePattern)
        #expect(SettingsStore(defaults: defaults).fileNamePattern == "ShotZ %Y-%m-%d at %H.%M.%S")
        defaults.set("Shotz custom %H", forKey: SettingsKey.fileNamePattern)
        #expect(SettingsStore(defaults: defaults).fileNamePattern == "Shotz custom %H")   // custom kept
    }
}
