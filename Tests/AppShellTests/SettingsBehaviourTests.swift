import Combine
import Foundation
import Testing
@testable import AppShell
import ShotzCore

@MainActor
struct SettingsBehaviourTests {
    @Test func playSoundsFlowsIntoCaptureOptions() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(settings.captureOptions().playSound)
        settings.playSounds = false
        #expect(!settings.captureOptions().playSound)
        settings.windowShadow = false
        settings.fileNamePattern = "Shot %H"
        let options = settings.captureOptions(paths: ShotzPaths(root: URL(filePath: "/tmp/r")))
        #expect(!options.includeWindowShadow)
        #expect(options.fileNamePattern == "Shot %H")
        #expect(options.destinationDirectory.lastPathComponent == "Captures")
    }

    @Test func afterCaptureActionsFollowSettings() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        #expect(AfterCaptureActions(settings: settings)
            == AfterCaptureActions(showQuickAccess: true, copyToClipboard: false, saveToExportFolder: false))
        settings.afterCaptureShowQuickAccess = false
        #expect(AfterCaptureActions(settings: settings).isSilent)
        settings.afterCaptureCopyToClipboard = true
        settings.afterCaptureSave = true
        let a = AfterCaptureActions(settings: settings)
        #expect(!a.showQuickAccess && a.copyToClipboard && a.saveToExportFolder && !a.isSilent)
    }

    @Test func devHotkeysNeverWritePreferences() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        // No apply(): registering ⌃⌥⌘3/4/5 here would compete with a real Shotz.
        let center = HotkeyCenter(settings: settings, devHotkeys: true, devProfile: false)
        #expect(center.mode == .standardDevHotkeys)
        #expect(center.binding(for: .captureArea) == .devArea)
        #expect(center.binding(for: .captureWindow) == nil)
        let devCenter = HotkeyCenter(settings: settings, devHotkeys: true, devProfile: true)
        #expect(devCenter.binding(for: .captureArea) == HotkeyBindings.devProfileArea)
        let written = settings.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("shortcuts.") }
        #expect(written.isEmpty)
        #expect(settings.hotkey(for: .captureArea) == .defaultArea)
    }

    @Test func bindingFollowsStoredValueLive() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let center = HotkeyCenter(settings: settings, devHotkeys: false, devProfile: false)
        let combo = KeyCombo(keyCode: 0x00, modifiers: [.control, .option, .command, .shift])
        settings.setHotkey(combo, for: .captureWindow)
        #expect(center.binding(for: .captureWindow) == combo)
        settings.setHotkey(nil, for: .captureArea)
        #expect(center.binding(for: .captureArea) == nil)
        settings.resetHotkeys()
        #expect(center.binding(for: .captureArea) == .defaultArea)
        #expect(center.binding(for: .captureWindow) == nil)
    }

    @Test func suspendedCenterRegistersNothingAndRecordsNoFailures() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        // Bind an unusual combo nothing else uses so registration is deterministic.
        settings.setHotkey(nil, for: .captureFullscreen)
        settings.setHotkey(nil, for: .captureArea)
        settings.setHotkey(nil, for: .captureAllInOne)
        settings.setHotkey(KeyCombo(keyCode: 0x6F, modifiers: [.control, .option, .shift, .command]), for: .captureWindow)
        let center = HotkeyCenter(settings: settings, devHotkeys: false, devProfile: false, registrar: FakeRegistrar())
        center.isSuspended = true
        center.apply()
        #expect(center.registrationFailures.isEmpty)
        center.isSuspended = false
        #expect(center.registrationFailures.isEmpty)
        center.shutdown()
    }

    /// Dev profile without --dev-hotkeys registers nothing, whatever is stored.
    @Test func devProfileRegistersNothing() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        settings.setHotkey(KeyCombo(keyCode: 0x00, modifiers: [.command, .option]), for: .captureWindow)
        let center = HotkeyCenter(settings: settings, devHotkeys: false, devProfile: true, registrar: FakeRegistrar())
        #expect(center.mode == .devProfileOff)
        #expect(center.registersNothing)
        center.apply()                       // safe: nothing to register
        #expect(center.registeredActions.isEmpty)
        #expect(center.registrationFailures.isEmpty)
        #expect(HotkeyAction.allCases.allSatisfy(center.isDevOverridden))
        center.shutdown()
    }

    @Test func screenRecordingStatusPollsOnlyWhileRequested() {
        var granted = false
        let status = ScreenRecordingStatus(check: { granted })
        #expect(!status.isPolling)
        status.startPolling()
        status.startPolling()
        #expect(status.isPolling)
        granted = true
        status.refresh()
        #expect(status.isGranted)
        status.stopPolling()
        #expect(status.isPolling)   // one client still showing it
        status.stopPolling()
        #expect(!status.isPolling)
        status.stopPolling()        // extra stop is harmless
        #expect(!status.isPolling)
    }
}
