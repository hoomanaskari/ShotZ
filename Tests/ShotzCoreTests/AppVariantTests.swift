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
        #expect(AppVariant.production.displayName == "Shotz")
        #expect(AppVariant.development.displayName == "Shotz Dev")
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
        #expect(dev.root.lastPathComponent == "Shotz Dev")
        #expect(dev.temporary.lastPathComponent == "Shotz Dev")
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
}
