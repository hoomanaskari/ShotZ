import Foundation
import Testing
@testable import ShotzCore

@MainActor
struct SettingsStoreTests {
    let suiteName = "ShotzTests-\(UUID().uuidString)"

    func makeStore() throws -> SettingsStore {
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return SettingsStore(defaults: defaults)
    }

    @Test func defaultsMatchSpec() throws {
        let s = try makeStore()
        #expect(s.launchAtLogin)
        #expect(s.showMenuBarIcon)
        #expect(s.playSounds)
        #expect(s.exportFolder == ShotzPaths.defaultExportFolder)
        #expect(s.afterCaptureShowQuickAccess)
        #expect(!s.afterCaptureCopyToClipboard)
        #expect(!s.afterCaptureSave)
        #expect(s.hotkey(for: .captureFullscreen) == .defaultFullscreen)
        #expect(s.hotkey(for: .captureArea) == .defaultArea)
        #expect(s.hotkey(for: .captureAllInOne) == .defaultAllInOne)
        #expect(s.hotkey(for: .captureWindow) == nil)
        #expect(s.hotkey(for: .restoreLastClosed) == nil)
        #expect(s.quickAccessSide == .left)
        #expect(s.quickAccessDisplay == .whereCaptured)
        #expect(s.quickAccessSize == .large)
        #expect(s.quickAccessAutoCloseSeconds == 0)
        #expect(s.quickAccessRemoveAfterDrag)
        #expect(!s.quickAccessCloseAfterCopy)
        #expect(s.quickAccessCloseAfterSave)
        #expect(!s.askDestinationWhenSaving)
        #expect(s.exportFormat == .png)
        #expect(s.retinaScale == .native)
        #expect(s.windowShadow)
        #expect(s.fileNamePattern == "Shotz %Y-%m-%d at %H.%M.%S")
        #expect(!s.editorReturnToSelect)
        #expect(s.editorSnapping)
        #expect(!s.editorCloseAfterCopy)
        #expect(!s.editorCloseAfterSave)
        #expect(s.historyRetention == .month)
    }

    @Test func roundTripAndReset() throws {
        let s = try makeStore()
        s.showMenuBarIcon = false
        s.quickAccessSize = .small
        s.exportFormat = .heic
        s.quickAccessAutoCloseSeconds = 10
        s.exportFolder = URL(filePath: "/tmp/shotz-export", directoryHint: .isDirectory)
        s.fileNamePattern = "X %H"

        let again = SettingsStore(defaults: s.defaults)
        #expect(!again.showMenuBarIcon)
        #expect(again.quickAccessSize == .small)
        #expect(again.exportFormat == .heic)
        #expect(again.quickAccessAutoCloseSeconds == 10)
        #expect(again.exportFolder.path(percentEncoded: false).hasPrefix("/tmp/shotz-export"))
        #expect(again.fileNamePattern == "X %H")

        again.resetAll()
        #expect(again.showMenuBarIcon)
        #expect(again.quickAccessSize == .large)
        #expect(again.exportFormat == .png)
    }

    @Test func hotkeysSetClearReset() throws {
        let s = try makeStore()
        let custom = KeyCombo(keyCode: 0x01, modifiers: [.control, .option])
        s.setHotkey(custom, for: .captureArea)
        #expect(s.hotkey(for: .captureArea) == custom)
        s.setHotkey(nil, for: .captureFullscreen)
        #expect(s.hotkey(for: .captureFullscreen) == nil)
        s.setHotkey(custom, for: .captureWindow)
        #expect(SettingsStore(defaults: s.defaults).hotkey(for: .captureWindow) == custom)
        s.resetHotkeys()
        #expect(s.hotkey(for: .captureArea) == .defaultArea)
        #expect(s.hotkey(for: .captureFullscreen) == .defaultFullscreen)
        #expect(s.hotkey(for: .captureWindow) == nil)
    }

    @Test func badStoredValuesFallBack() throws {
        let s = try makeStore()
        s.defaults.set("bogus", forKey: SettingsKey.quickAccessSide)
        s.defaults.set(Data([1, 2, 3]), forKey: SettingsKey.hotkey(.captureArea))
        #expect(s.quickAccessSide == .left)
        #expect(s.hotkey(for: .captureArea) == .defaultArea)
    }

    @Test func exportConfigurationReadsSameKeys() throws {
        let s = try makeStore()
        #expect(ExportConfiguration.current(defaults: s.defaults) == ExportConfiguration())
        s.exportFormat = .jpeg
        s.retinaScale = .downscaleTo1x
        let config = ExportConfiguration.current(defaults: s.defaults)
        #expect(config.format == .jpeg)
        #expect(config.retinaScale == .downscaleTo1x)
    }

    @Test func captureOptionsFromSettings() throws {
        let s = try makeStore()
        s.windowShadow = false
        s.playSounds = false
        let paths = ShotzPaths(root: URL(filePath: "/tmp/shotz-root", directoryHint: .isDirectory))
        let options = s.captureOptions(paths: paths)
        #expect(!options.includeWindowShadow)
        #expect(!options.playSound)
        #expect(options.destinationDirectory == paths.captures)
    }
}
