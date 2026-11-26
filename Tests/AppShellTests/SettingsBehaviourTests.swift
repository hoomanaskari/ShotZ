import Combine
import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

@MainActor
struct SettingsBehaviourTests {
    @Test func playSoundsFlowsIntoCaptureOptions() {
        let (settings, _) = makeSettings()
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
        let (settings, _) = makeSettings()
        #expect(AfterCaptureActions(settings: settings)
            == AfterCaptureActions(showQuickAccess: true, copyToClipboard: false, saveToExportFolder: false))
        settings.afterCaptureShowQuickAccess = false
        #expect(AfterCaptureActions(settings: settings).isSilent)
        settings.afterCaptureCopyToClipboard = true
        settings.afterCaptureSave = true
        let a = AfterCaptureActions(settings: settings)
        #expect(!a.showQuickAccess && a.copyToClipboard && a.saveToExportFolder && !a.isSilent)
    }

    /// Each variant's defaults come from `AppVariant`; nothing is written until the user records.
    @Test func variantDefaultsAreNotWritten() {
        let (settings, _) = makeSettings()
        let dev = SettingsStore(defaults: settings.defaults, variant: .development)
        #expect(settings.hotkey(for: .captureArea) == .defaultArea)
        #expect(dev.hotkey(for: .captureArea) == .devArea)
        #expect(settings.launchAtLogin && !dev.launchAtLogin)
        let written = settings.defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("shortcuts.") }
        #expect(written.isEmpty)
    }

    @Test func bindingFollowsStoredValueLive() {
        let (settings, _) = makeSettings()
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: true, registrar: FakeRegistrar())
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
        let (settings, _) = makeSettings()
        // Bind an unusual combo nothing else uses so registration is deterministic.
        settings.setHotkey(nil, for: .captureFullscreen)
        settings.setHotkey(nil, for: .captureArea)
        settings.setHotkey(nil, for: .captureAllInOne)
        settings.setHotkey(KeyCombo(keyCode: 0x6F, modifiers: [.control, .option, .shift, .command]), for: .captureWindow)
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: true, registrar: FakeRegistrar())
        center.isSuspended = true
        center.apply()
        #expect(center.registrationFailures.isEmpty)
        center.isSuspended = false
        #expect(center.registrationFailures.isEmpty)
        center.shutdown()
    }

    /// `--no-hotkeys` registers nothing, whatever is stored, and logs why.
    @Test func noHotkeysRunRegistersNothing() {
        let (settings, _) = makeSettings()
        settings.setHotkey(KeyCombo(keyCode: 0x00, modifiers: [.command, .option]), for: .captureWindow)
        let fake = FakeRegistrar()
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: false, registrar: fake)
        #expect(center.registersNothing)
        center.apply()
        #expect(center.registeredActions.isEmpty)
        #expect(fake.active.isEmpty)
        #expect(center.registrationFailures.isEmpty)
        #expect(settings.hotkey(for: .captureArea) == .defaultArea)   // stored values untouched
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
