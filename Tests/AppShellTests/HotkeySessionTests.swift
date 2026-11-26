import Carbon.HIToolbox
import Foundation
import Testing
@testable import AppShell
import ShotzCore

/// Stands in for Carbon: records registrations and fails chosen combos.
@MainActor final class FakeRegistrar: HotkeyRegistrar {
    var failing: [KeyCombo: OSStatus] = [:]
    private(set) var active: [UInt32: KeyCombo] = [:]

    func register(_ combo: KeyCombo, id: UInt32) -> OSStatus {
        if let status = failing[combo] { return status }
        active[id] = combo
        return noErr
    }

    func unregister(id: UInt32) { active[id] = nil }
}

@MainActor
struct HotkeySessionTests {
    let recorded = KeyCombo(keyCode: 0x0F, modifiers: [.command, .option])   // ⌥⌘R

    // MARK: "Recorded but inactive this session", all four modes

    @Test func sessionStatusForARecordedShortcutInEveryMode() {
        func status(_ action: HotkeyAction, _ mode: HotkeyMode) -> HotkeyBindings.SessionStatus {
            HotkeyBindings.sessionStatus(for: action, stored: recorded, mode: mode)
        }
        for action in HotkeyAction.allCases {
            #expect(status(action, .standard) == .active)
            #expect(status(action, .devProfileOff) == .inactive(effective: nil))
        }
        #expect(status(.captureArea, .standardDevHotkeys) == .inactive(effective: .devArea))
        #expect(status(.captureFullscreen, .standardDevHotkeys) == .inactive(effective: .devFullscreen))
        #expect(status(.captureAllInOne, .standardDevHotkeys) == .inactive(effective: .devAllInOne))
        #expect(status(.captureWindow, .standardDevHotkeys) == .active)
        #expect(status(.restoreLastClosed, .standardDevHotkeys) == .active)
        #expect(status(.captureArea, .devProfileDevHotkeys) == .inactive(effective: HotkeyBindings.devProfileArea))
        #expect(status(.captureWindow, .devProfileDevHotkeys) == .inactive(effective: nil))
        // Recording exactly the session's combo is active.
        #expect(HotkeyBindings.sessionStatus(for: .captureArea, stored: .devArea, mode: .standardDevHotkeys) == .active)
        // Clearing a shortcut under --dev-hotkeys is not active either (the dev combo stays).
        #expect(HotkeyBindings.sessionStatus(for: .captureArea, stored: nil, mode: .standardDevHotkeys) == .inactive(effective: .devArea))
    }

    @Test func inactiveMessagesSayWhyAndWhatIsUsed() {
        let dev = HotkeyBindings.inactiveMessage(for: .captureArea, mode: .standardDevHotkeys, effective: .devArea)
        #expect(dev.hasPrefix("Saved, but not active in this session"))
        #expect(dev.contains("--dev-hotkeys"))
        #expect(dev.contains("⌃⌥⌘4"))
        #expect(dev.contains("relaunch normally"))
        let off = HotkeyBindings.inactiveMessage(for: .captureArea, mode: .devProfileOff, effective: nil)
        #expect(off.contains("dev profile") && off.contains("--dev-hotkeys"))
        let hyper = HotkeyBindings.inactiveMessage(for: .captureArea, mode: .devProfileDevHotkeys, effective: HotkeyBindings.devProfileArea)
        #expect(hyper.contains("⌃⌥⇧⌘4"))
        let none = HotkeyBindings.inactiveMessage(for: .captureWindow, mode: .devProfileDevHotkeys, effective: nil)
        #expect(none.contains("Capture Window"))
    }

    @Test func centerReportsSessionStatusFromStoredSettings() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        settings.setHotkey(recorded, for: .captureArea)
        let modes: [(Bool, Bool, HotkeyBindings.SessionStatus)] = [
            (false, false, .active),
            (false, true, .inactive(effective: .devArea)),
            (true, false, .inactive(effective: nil)),
            (true, true, .inactive(effective: HotkeyBindings.devProfileArea)),
        ]
        for (devProfile, devHotkeys, expected) in modes {
            let center = HotkeyCenter(settings: settings, devHotkeys: devHotkeys, devProfile: devProfile, registrar: FakeRegistrar())
            #expect(center.sessionStatus(for: .captureArea) == expected, "devProfile \(devProfile), devHotkeys \(devHotkeys)")
        }
    }

    // MARK: Carbon failure surfaces in Settings and onboarding

    @Test func registrationFailureSurfacesAsWarningInSettingsAndOnboarding() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let fake = FakeRegistrar()
        fake.failing[.defaultArea] = OSStatus(eventHotKeyExistsErr)
        let center = HotkeyCenter(settings: settings, devHotkeys: false, devProfile: false, registrar: fake)
        center.apply()

        #expect(center.registrationFailures == [.captureArea: OSStatus(eventHotKeyExistsErr)])
        #expect(center.registeredActions == [.captureFullscreen, .captureAllInOne])
        // Settings row warning (the triangle and the orange line use this text).
        let warning = center.registrationWarning(for: .captureArea)
        #expect(warning?.contains("⇧⌘4") == true)
        #expect(warning?.contains("\(eventHotKeyExistsErr)") == true)
        #expect(center.registrationWarning(for: .captureFullscreen) == nil)

        // Onboarding shortcuts step.
        let onboarding = OnboardingModel(
            settings: settings, hotkeys: center,
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/Shotz.app")),
            screenRecording: ScreenRecordingStatus(check: { false })
        )
        #expect(onboarding.heldByAnotherApp == [.captureArea])
        #expect(onboarding.canOfferAlternates)

        // Fixing it (a different combo that registers) clears the warning.
        settings.setHotkey(KeyCombo(keyCode: 0x15, modifiers: [.command, .option, .shift]), for: .captureArea)
        center.apply()
        #expect(center.registrationFailures.isEmpty)
        #expect(center.registrationWarning(for: .captureArea) == nil)
        #expect(onboarding.heldByAnotherApp.isEmpty)
    }

    @Test func failureUnderDevHotkeysStillWarnsButOffersNoAlternates() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let fake = FakeRegistrar()
        fake.failing[.devArea] = OSStatus(eventHotKeyExistsErr)
        let center = HotkeyCenter(settings: settings, devHotkeys: true, devProfile: false, registrar: fake)
        center.apply()
        #expect(center.registrationWarning(for: .captureArea)?.contains("⌃⌥⌘4") == true)
        let onboarding = OnboardingModel(
            settings: settings, hotkeys: center,
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/Shotz.app")),
            screenRecording: ScreenRecordingStatus(check: { false })
        )
        #expect(onboarding.heldByAnotherApp == [.captureArea])
        #expect(!onboarding.canOfferAlternates)
    }

    @Test func suspendAndResumeGoThroughTheRegistrar() {
        let (settings, suite) = makeSettings()
        defer { UserDefaults().removePersistentDomain(forName: suite) }
        let fake = FakeRegistrar()
        let center = HotkeyCenter(settings: settings, devHotkeys: false, devProfile: false, registrar: fake)
        center.apply()
        #expect(fake.active.count == 3)
        center.isSuspended = true
        #expect(fake.active.isEmpty)
        center.isSuspended = false
        #expect(fake.active.count == 3)
        center.shutdown()
        #expect(fake.active.isEmpty)
    }

    // MARK: Log lines

    @Test func logLines() {
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, effective: .defaultArea, mode: .standard, failure: nil)
            == "Hotkey captureArea = ⇧⌘4: registered")
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, effective: .defaultArea, mode: .standard, failure: -9878)
            == "Hotkey captureArea = ⇧⌘4: FAILED (Carbon status -9878)")
        let overridden = HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, effective: .devArea, mode: .standardDevHotkeys, failure: nil)
        #expect(overridden.hasPrefix("Hotkey captureArea = ⌃⌥⌘4: registered; stored ⇧⌘4 overridden this session"))
        #expect(HotkeyBindings.logLine(for: .captureWindow, stored: nil, effective: nil, mode: .standard, failure: nil)
            == "Hotkey captureWindow: not registered (no stored shortcut)")
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, effective: nil, mode: .devProfileOff, failure: nil)
            .hasPrefix("Hotkey captureArea: not registered; stored ⇧⌘4 overridden this session (dev profile"))
    }

    @Test func relaunchNormallyDropsDevHotkeys() {
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--dev-hotkeys"], devProfile: false, keepDevHotkeys: false).isEmpty)
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--dev-hotkeys"], devProfile: true, keepDevHotkeys: false) == ["--dev-profile"])
    }
}
