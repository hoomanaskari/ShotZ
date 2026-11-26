import Carbon.HIToolbox
import Foundation
import Testing
@testable import AppShell
import ShotzCore

struct HotkeyBindingTests {
    let custom = KeyCombo(keyCode: 0x01, modifiers: [.command, .option])

    @Test func devFlagDetection() {
        #expect(HotkeyCenter.devHotkeysRequested(arguments: ["Shotz", "--dev-hotkeys"], environment: [:]))
        #expect(HotkeyCenter.devHotkeysRequested(arguments: ["Shotz"], environment: ["SHOTZ_DEV_HOTKEYS": "1"]))
        #expect(!HotkeyCenter.devHotkeysRequested(arguments: ["Shotz"], environment: ["SHOTZ_DEV_HOTKEYS": "0"]))
        #expect(!HotkeyCenter.devHotkeysRequested(arguments: ["Shotz"], environment: [:]))
    }

    @Test func devOverridesCaptureBindingsOnly() {
        #expect(HotkeyBindings.effective(for: .captureArea, stored: .defaultArea, dev: true) == .devArea)
        #expect(HotkeyBindings.effective(for: .captureFullscreen, stored: nil, dev: true) == .devFullscreen)
        #expect(HotkeyBindings.effective(for: .captureAllInOne, stored: custom, dev: true) == .devAllInOne)
        #expect(HotkeyBindings.effective(for: .captureWindow, stored: custom, dev: true) == custom)
        #expect(HotkeyBindings.effective(for: .restoreLastClosed, stored: nil, dev: true) == nil)
        #expect(HotkeyBindings.effective(for: .captureArea, stored: custom, dev: false) == custom)
        #expect(HotkeyBindings.effective(for: .captureArea, stored: nil, dev: false) == nil)
        #expect(HotkeyBindings.isDevOverridden(.captureArea, dev: true))
        #expect(!HotkeyBindings.isDevOverridden(.captureWindow, dev: true))
        #expect(!HotkeyBindings.isDevOverridden(.captureArea, dev: false))
    }

    @MainActor @Test func effectiveAllSkipsUnbound() {
        let all = HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkey(for: $0) }, dev: false)
        #expect(all == [.captureFullscreen: .defaultFullscreen, .captureArea: .defaultArea, .captureAllInOne: .defaultAllInOne])
    }

    @Test func planRegistersOnlyChanges() {
        let registered: [HotkeyAction: KeyCombo] = [.captureArea: .defaultArea, .captureFullscreen: .defaultFullscreen]
        #expect(HotkeyBindings.plan(registered: registered, desired: registered).isEmpty)

        var desired = registered
        desired[.captureArea] = custom
        desired[.captureWindow] = .devArea
        desired[.captureFullscreen] = nil
        let plan = HotkeyBindings.plan(registered: registered, desired: desired)
        #expect(plan.unregister == [.captureArea, .captureFullscreen])
        #expect(plan.register == [.captureArea, .captureWindow])
    }

    @Test func planHandlesSwapsAndRetriesFailures() {
        let registered: [HotkeyAction: KeyCombo] = [.captureArea: .defaultArea, .captureFullscreen: .defaultFullscreen]
        let swapped: [HotkeyAction: KeyCombo] = [.captureArea: .defaultFullscreen, .captureFullscreen: .defaultArea]
        let plan = HotkeyBindings.plan(registered: registered, desired: swapped)
        #expect(plan.unregister == [.captureArea, .captureFullscreen])
        #expect(plan.register == [.captureArea, .captureFullscreen])

        // A failed action is never in `registered`, so it is retried.
        let retry = HotkeyBindings.plan(registered: [:], desired: [.captureAllInOne: .defaultAllInOne], failed: [.captureAllInOne])
        #expect(retry.register == [.captureAllInOne])
    }

    @Test func duplicatesFound() {
        let bindings: [HotkeyAction: KeyCombo] = [.captureArea: custom, .captureWindow: custom, .captureFullscreen: .defaultFullscreen]
        #expect(HotkeyBindings.duplicates(in: bindings) == [.captureWindow])
        #expect(HotkeyBindings.duplicates(in: [:]).isEmpty)
    }

    @Test func carbonModifiers() {
        #expect(HotkeyCenter.carbonModifiers([.command, .shift]) == UInt32(cmdKey | shiftKey))
        #expect(HotkeyCenter.carbonModifiers([.control, .option, .command]) == UInt32(controlKey | optionKey | cmdKey))
        #expect(HotkeyCenter.carbonModifiers([]) == 0)
    }

    @Test func uniqueCarbonIDs() {
        let ids = HotkeyAction.allCases.map(HotkeyCenter.carbonID)
        #expect(Set(ids).count == ids.count)
        #expect(!ids.contains(0))
    }
}

struct ShortcutValidationTests {
    let key4 = KeyCombo.keyCode4

    @Test func acceptsNormalShortcut() {
        #expect(ShortcutValidation.problem(for: .defaultArea, action: .captureArea, current: [:]) == nil)
        // Re-recording the action's own current combo is fine.
        #expect(ShortcutValidation.problem(for: .defaultArea, action: .captureArea, current: [.captureArea: .defaultArea]) == nil)
    }

    @Test func requiresAStrongModifierExceptFunctionKeys() {
        #expect(ShortcutValidation.problem(for: KeyCombo(keyCode: key4, modifiers: []), action: .captureArea, current: [:]) == .needsModifier)
        #expect(ShortcutValidation.problem(for: KeyCombo(keyCode: key4, modifiers: [.shift]), action: .captureArea, current: [:]) == .needsModifier)
        #expect(ShortcutValidation.problem(for: KeyCombo(keyCode: key4, modifiers: [.option]), action: .captureArea, current: [:]) == nil)
        let f5 = KeyCombo(keyCode: 0x60, modifiers: [])
        #expect(ShortcutValidation.problem(for: f5, action: .captureArea, current: [:]) == nil)
    }

    @Test func rejectsReservedAndDuplicatesAndUnknownKeys() {
        let cmdShift6 = KeyCombo(keyCode: 0x16, modifiers: [.command, .shift])
        #expect(ShortcutValidation.problem(for: cmdShift6, action: .captureWindow, current: [:]) == .reserved)
        #expect(ShortcutValidation.problem(for: .defaultArea, action: .captureWindow, current: [.captureArea: .defaultArea])
            == .duplicate(.captureArea))
        #expect(ShortcutValidation.problem(for: KeyCombo(keyCode: 0x35, modifiers: [.command]), action: .captureArea, current: [:])
            == .unsupportedKey)
    }

    @Test func keyNamesAndMenuEquivalents() {
        #expect(KeyNames.display(.devArea) == "⌃⌥⌘4")
        #expect(KeyNames.display(.defaultFullscreen) == "⇧⌘3")
        #expect(KeyNames.display(KeyCombo(keyCode: 0x60, modifiers: [.shift])) == "⇧F5")
        #expect(KeyNames.menuKeyEquivalent(.defaultArea) == "4")
        #expect(KeyNames.menuKeyEquivalent(KeyCombo(keyCode: 0x00, modifiers: [.command])) == "a")
        #expect(KeyNames.menuKeyEquivalent(KeyCombo(keyCode: 0xFF, modifiers: [.command])) == "")
        #expect(KeyNames.modifiers(from: [.command, .shift, .capsLock]) == [.command, .shift])
        #expect(KeyNames.menuModifierMask([.control, .option]) == [.control, .option])
    }
}
