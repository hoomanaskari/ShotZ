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

    @Test func modeResolution() {
        #expect(HotkeyMode.resolve(devProfile: false, devHotkeys: false) == .standard)
        #expect(HotkeyMode.resolve(devProfile: false, devHotkeys: true) == .standardDevHotkeys)
        #expect(HotkeyMode.resolve(devProfile: true, devHotkeys: false) == .devProfileOff)
        #expect(HotkeyMode.resolve(devProfile: true, devHotkeys: true) == .devProfileDevHotkeys)
        #expect(HotkeyMode.standard.sessionNote == nil)
        #expect(HotkeyMode.devProfileOff.sessionNote != nil)
    }

    /// The full selection matrix: 4 modes × 5 actions, with every action
    /// stored as a custom combo so overrides are visible.
    @Test func bindingSelectionMatrix() {
        let stored: [HotkeyAction: KeyCombo] = [
            .captureFullscreen: .defaultFullscreen, .captureArea: .defaultArea, .captureAllInOne: .defaultAllInOne,
            .captureWindow: custom, .restoreLastClosed: KeyCombo(keyCode: 0x0F, modifiers: [.command, .option]),
        ]
        func row(_ mode: HotkeyMode) -> [HotkeyAction: KeyCombo] {
            HotkeyBindings.effectiveAll(stored: { stored[$0] }, mode: mode)
        }
        #expect(row(.standard) == stored)
        #expect(row(.standardDevHotkeys) == [
            .captureFullscreen: .devFullscreen, .captureArea: .devArea, .captureAllInOne: .devAllInOne,
            .captureWindow: custom, .restoreLastClosed: stored[.restoreLastClosed]!,
        ])
        #expect(row(.devProfileOff).isEmpty)
        #expect(row(.devProfileDevHotkeys) == [
            .captureFullscreen: HotkeyBindings.devProfileFullscreen,
            .captureArea: HotkeyBindings.devProfileArea,
            .captureAllInOne: HotkeyBindings.devProfileAllInOne,
        ])
        // Unbound stays unbound outside the forced capture set.
        #expect(HotkeyBindings.effective(for: .captureArea, stored: nil, mode: .standard) == nil)
        #expect(HotkeyBindings.effective(for: .captureWindow, stored: nil, mode: .standardDevHotkeys) == nil)
        #expect(!HotkeyBindings.isOverridden(.captureArea, mode: .standard))
        #expect(HotkeyBindings.isOverridden(.captureWindow, mode: .devProfileOff))
    }

    /// A dev instance must never share a combo with the owner's instance,
    /// whether the owner runs normally or with --dev-hotkeys.
    @Test func devProfileCombosNeverCollideWithOwnerCombos() {
        let owner = Set(HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkeyNonisolated($0) }, mode: .standard).values)
            .union(HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkeyNonisolated($0) }, mode: .standardDevHotkeys).values)
        let dev = Set(HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkeyNonisolated($0) }, mode: .devProfileDevHotkeys).values)
        #expect(dev.count == 3)
        #expect(owner.isDisjoint(with: dev))
        #expect(HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkeyNonisolated($0) }, mode: .devProfileOff).isEmpty)
        #expect(KeyNames.display(HotkeyBindings.devProfileArea) == "⌃⌥⇧⌘4")
    }

    @MainActor @Test func effectiveAllSkipsUnbound() {
        let all = HotkeyBindings.effectiveAll(stored: { SettingsStore.defaultHotkey(for: $0) }, mode: .standard)
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

extension SettingsStore {
    /// `defaultHotkey(for:)` is main-actor isolated only by its class; it is pure.
    nonisolated static func defaultHotkeyNonisolated(_ action: HotkeyAction) -> KeyCombo? {
        switch action {
        case .captureFullscreen: .defaultFullscreen
        case .captureArea: .defaultArea
        case .captureAllInOne: .defaultAllInOne
        case .captureWindow, .restoreLastClosed: nil
        }
    }
}
