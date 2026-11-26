import Carbon.HIToolbox
import Foundation
import Testing
@testable import AppShell
import ShotzCore

struct HotkeyCenterTests {
    @Test func devFlagDetection() {
        #expect(HotkeyCenter.devHotkeysRequested(arguments: ["Shotz", "--dev-hotkeys"], environment: [:]))
        #expect(HotkeyCenter.devHotkeysRequested(arguments: ["Shotz"], environment: ["SHOTZ_DEV_HOTKEYS": "1"]))
        #expect(!HotkeyCenter.devHotkeysRequested(arguments: ["Shotz"], environment: ["SHOTZ_DEV_HOTKEYS": "0"]))
    }

    @Test func devOverridesCaptureBindingsOnly() {
        let custom = KeyCombo(keyCode: 0x01, modifiers: [.command])
        #expect(HotkeyCenter.effectiveBinding(for: .captureArea, stored: .defaultArea, dev: true) == .devArea)
        #expect(HotkeyCenter.effectiveBinding(for: .captureFullscreen, stored: nil, dev: true) == .devFullscreen)
        #expect(HotkeyCenter.effectiveBinding(for: .captureAllInOne, stored: custom, dev: true) == .devAllInOne)
        #expect(HotkeyCenter.effectiveBinding(for: .captureWindow, stored: custom, dev: true) == custom)
        #expect(HotkeyCenter.effectiveBinding(for: .captureArea, stored: custom, dev: false) == custom)
    }

    @Test func carbonModifiers() {
        #expect(HotkeyCenter.carbonModifiers([.command, .shift]) == UInt32(cmdKey | shiftKey))
        #expect(HotkeyCenter.carbonModifiers([.control, .option, .command]) == UInt32(controlKey | optionKey | cmdKey))
    }

    @Test func uniqueCarbonIDs() {
        let ids = HotkeyAction.allCases.map(HotkeyCenter.carbonID)
        #expect(Set(ids).count == ids.count)
    }

    @Test func symbolicHotKeyParsing() {
        let allOff: [String: Any] = Dictionary(uniqueKeysWithValues: [28, 29, 30, 31, 184].map { (String($0), ["enabled": false] as [String: Any]) })
        #expect(!Permissions.screenshotShortcutsEnabled(in: allOff))
        var oneOn = allOff
        oneOn["29"] = ["enabled": true]
        #expect(Permissions.screenshotShortcutsEnabled(in: oneOn))
        var missing = allOff
        missing["184"] = nil
        #expect(Permissions.screenshotShortcutsEnabled(in: missing))
    }
}
