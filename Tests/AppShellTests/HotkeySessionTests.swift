import Carbon.HIToolbox
import Foundation
import Testing
import ShotzTestSupport
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
    func onboarding(_ settings: SettingsStore, _ center: HotkeyCenter) -> OnboardingModel {
        OnboardingModel(
            settings: settings, hotkeys: center,
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/Shotz.app"), variant: .production),
            screenRecording: ScreenRecordingStatus(check: { false })
        )
    }

    // MARK: --no-hotkeys

    @Test func noHotkeysDetection() {
        func off(_ args: [String], _ env: [String: String] = [:]) -> Bool {
            HotkeyCenter.hotkeysDisabledRequested(arguments: ["/x/Shotz"] + args, environment: env)
        }
        #expect(!off([]))
        #expect(off(["--no-hotkeys"]))
        #expect(off(["--debug-present", "/a.png"]))
        #expect(off(["--debug-snapshot-ui", "/tmp/x"]))
        #expect(off(["-QuickAccessSelfTest", "/tmp/r.json"]))
        #expect(off([], ["SHOTZ_EDITOR_SCRIPT": "/tmp/s.json"]))
        #expect(!off(["-quickAccess.side", "right"]))
        #expect(!HotkeyCenter.hotkeysDisabledRequested(arguments: ["--no-hotkeys"], environment: [:]))   // argv[0] only
    }

    @Test func effectiveBindingIsStoredOrNothing() {
        let stored = KeyCombo(keyCode: 0x0F, modifiers: [.command, .option])
        for action in HotkeyAction.allCases {
            #expect(HotkeyBindings.effective(for: action, stored: stored, enabled: true) == stored)
            #expect(HotkeyBindings.effective(for: action, stored: stored, enabled: false) == nil)
        }
    }

    // MARK: Alternates never collide with either variant's defaults

    @Test func alternatesAreDistinctFromBothVariantsDefaults() {
        let defaults = Set(AppVariant.allCases.flatMap { v in HotkeyAction.allCases.compactMap { v.defaultHotkey(for: $0) } })
        for variant in AppVariant.allCases {
            let alternates = Set(HotkeyBindings.alternates(for: variant).values)
            #expect(alternates.count == 3)
            #expect(alternates.isDisjoint(with: defaults), "\(variant)")
        }
        #expect(Set(HotkeyBindings.alternates(for: .production).values)
            .isDisjoint(with: Set(HotkeyBindings.alternates(for: .development).values)))
        #expect(HotkeyBindings.alternatesTitle(for: .production) == "Use ⌥⇧⌘3, ⌥⇧⌘4 and ⌥⇧⌘5")
    }

    // MARK: Carbon failure surfaces in Settings and onboarding

    @Test func registrationFailureSurfacesAsWarningInSettingsAndOnboarding() {
        let (settings, _) = makeSettings()
        let fake = FakeRegistrar()
        fake.failing[.defaultArea] = OSStatus(eventHotKeyExistsErr)
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: true, registrar: fake)
        center.apply()

        #expect(center.registrationFailures == [.captureArea: OSStatus(eventHotKeyExistsErr)])
        #expect(center.registeredActions == [.captureFullscreen, .captureAllInOne])
        let warning = center.registrationWarning(for: .captureArea)
        #expect(warning?.contains("⇧⌘4") == true)
        #expect(warning?.contains("\(eventHotKeyExistsErr)") == true)
        #expect(center.registrationWarning(for: .captureFullscreen) == nil)

        let model = onboarding(settings, center)
        #expect(model.heldByAnotherApp == [.captureArea])
        #expect(model.canOfferAlternates)
        model.useAlternateShortcuts()
        #expect(settings.hotkey(for: .captureArea) == HotkeyBindings.alternates(for: .production)[.captureArea])
        center.apply()
        #expect(center.registrationFailures.isEmpty)
        #expect(center.registrationWarning(for: .captureArea) == nil)
        #expect(model.heldByAnotherApp.isEmpty)
    }

    @Test func suspendAndResumeGoThroughTheRegistrar() {
        let (settings, _) = makeSettings()
        let fake = FakeRegistrar()
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: true, registrar: fake)
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
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, enabled: true, failure: nil)
            == "Hotkey captureArea = ⇧⌘4: registered")
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .defaultArea, enabled: true, failure: -9878)
            == "Hotkey captureArea = ⇧⌘4: FAILED (Carbon status -9878)")
        #expect(HotkeyBindings.logLine(for: .captureArea, stored: .devArea, enabled: false, failure: nil)
            == "Hotkey captureArea: not registered (--no-hotkeys); stored ⌃⌥⌘4")
        #expect(HotkeyBindings.logLine(for: .captureWindow, stored: nil, enabled: true, failure: nil)
            == "Hotkey captureWindow: not registered (no stored shortcut)")
    }

    @Test func relaunchKeepsOnlyNoHotkeys() {
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--no-hotkeys", "--debug-edit", "/a.png"]) == ["--no-hotkeys"])
        #expect(Permissions.relaunchArguments(from: ["/x/Shotz", "--debug-edit", "/a.png"]).isEmpty)
        #expect(Permissions.relaunchArguments(from: ["--no-hotkeys"]).isEmpty)
    }
}
