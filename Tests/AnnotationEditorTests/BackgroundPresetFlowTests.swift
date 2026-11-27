import AnnotationKit
import AppKit
import Testing
@testable import AnnotationEditor
import ShotzTestSupport
@testable import ShotzUI

/// Background presets end to end, through the panel's real controls and real sheets.
@MainActor
struct BackgroundPresetFlowTests {
    typealias F = BackgroundPanelInteractionTests

    static func button(_ title: String, in view: NSView) -> ShotzButton? {
        PointerDriver.all(ShotzButton.self, in: view).first { $0.title == title }
    }

    static func sheetButton(_ title: String, in sheet: NSWindow) -> NSButton? {
        PointerDriver.all(NSButton.self, in: sheet.contentView!).first { $0.title == title }
    }

    @Test func saveApplyRelaunchAndDelete() async throws {
        let f = F.fixture(.init(fill: .solid(RGBAColor(red: 0.2, green: 0.4, blue: 0.8)), padding: 0.12, cornerRadius: 30, shadow: .strong))
        let saved = try #require(f.style)

        // Save…: the sheet opens with the insertion point in the name field and Save disabled.
        let save = try #require(Self.button("Save…", in: f.panel))
        await PointerDriver.click(save, at: f.centre(save))
        let sheet = try #require(f.window.attachedSheet, "the name sheet")
        let name = try #require(PointerDriver.all(ShotzTextField.self, in: sheet.contentView!).first)
        let editor = sheet.firstResponder as? NSTextView
        #expect(editor?.isFieldEditor == true && (editor?.delegate as AnyObject?) === name.editingView,
                "typing goes into the name field (first responder: \(String(describing: sheet.firstResponder)))")
        let saveButton = try #require(Self.sheetButton("Save", in: sheet))
        #expect(!saveButton.isEnabled, "no name, no saving")
        // Typing: what a key press does in the field editor.
        editor?.insertText("Sunset", replacementRange: NSRange(location: NSNotFound, length: 0))
        #expect(name.text == "Sunset")
        #expect(saveButton.isEnabled)
        saveButton.performClick(nil)
        await PointerDriver.settleAsync()

        // It is stored and listed immediately.
        #expect(BackgroundPresets(defaults: f.presetsDefaults).saved.map(\.name) == ["Sunset"])
        var popup = try #require(f.control(ShotzPopUpButton.self, "Saved presets"))
        #expect(popup.items == ["Sunset"] && popup.isEnabled)

        // Change the background, then apply the preset from the pop-up's menu.
        let shadow = try #require(f.control(ShotzSegmentedControl.self, "Shadow"))
        await f.clickSegment(shadow, 0, of: 3)
        #expect(f.style?.shadow == .off)
        popup = try #require(f.control(ShotzPopUpButton.self, "Saved presets"))
        popup.items = ["Sunset", "x"]   // so the menu has another item to come from…
        popup.selectedIndex = 1
        popup.choiceMenu.performActionForItem(at: 0)
        await PointerDriver.settleAsync()
        #expect(f.style == saved, "applying the preset restores it")

        // Survives relaunch: a new store and panel on the same preferences.
        let reopened = BackgroundPanelView(model: f.model, presets: BackgroundPresets(defaults: f.presetsDefaults))
        reopened.layoutSubtreeIfNeeded()
        #expect(PointerDriver.all(ShotzPopUpButton.self, in: reopened).first { $0.accessibilityLabel() == "Saved presets" }?.items == ["Sunset"])

        // Delete…: confirm, and the list is empty again.
        let delete = try #require(Self.button("Delete…", in: f.panel))
        await PointerDriver.click(delete, at: f.centre(delete))
        let confirm = try #require(f.window.attachedSheet, "the delete confirmation")
        try #require(Self.sheetButton("Delete", in: confirm)).performClick(nil)
        await PointerDriver.settleAsync()
        #expect(BackgroundPresets(defaults: f.presetsDefaults).saved.isEmpty)
        #expect(f.control(ShotzPopUpButton.self, "Saved presets")?.items == ["None saved"])
    }

    @Test func returnWithoutANameSavesNothing() async throws {
        let f = F.fixture(.init(padding: 0.1))
        let save = try #require(Self.button("Save…", in: f.panel))
        await PointerDriver.click(save, at: f.centre(save))
        let sheet = try #require(f.window.attachedSheet)
        let saveButton = try #require(Self.sheetButton("Save", in: sheet))
        #expect(!saveButton.isEnabled)
        saveButton.performClick(nil)   // a disabled button does nothing
        #expect(f.window.attachedSheet != nil, "the sheet stays open")
        try #require(Self.sheetButton("Cancel", in: sheet)).performClick(nil)
        await PointerDriver.settleAsync()
        #expect(BackgroundPresets(defaults: f.presetsDefaults).saved.isEmpty)
    }
}
