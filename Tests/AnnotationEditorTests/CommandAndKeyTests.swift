import AnnotationKit
import CoreGraphics
import Foundation
import Testing
@testable import AnnotationEditor

@MainActor
struct CommandTests {
    private func threeRects() -> EditorModel {
        let m = makeModel(tool: .rectangle)
        for x in [100, 300, 500] as [CGFloat] { m.drag(CGPoint(x: x, y: 100), CGPoint(x: x + 100, y: 200)) }
        m.setTool(.select)
        return m
    }

    @Test func zOrder() {
        let m = threeRects()
        let ids = m.objects.map(\.id)
        m.select([ids[0]])
        m.arrange(.forward)
        #expect(m.objects.map(\.id) == [ids[1], ids[0], ids[2]])
        m.arrange(.front)
        #expect(m.objects.map(\.id) == [ids[1], ids[2], ids[0]])
        m.arrange(.back)
        #expect(m.objects.map(\.id) == [ids[0], ids[1], ids[2]])
        m.select([ids[2]])
        m.arrange(.backward)
        #expect(m.objects.map(\.id) == [ids[0], ids[2], ids[1]])
    }

    @Test func duplicateNudgeDeleteSelectAll() {
        let m = threeRects()
        m.select([m.objects[0].id])
        m.duplicateSelection()
        #expect(m.objects.count == 4)
        #expect(m.selection == [m.objects[3].id])
        m.nudge(dx: 10, dy: -1)
        let moved = rect(of: m.objects[3])
        let original = rect(of: m.objects[0])
        #expect(moved != nil && original != nil)
        m.selectAll()
        #expect(m.selection.count == 4)
        m.deleteSelection()
        #expect(m.objects.isEmpty)
        m.store.undo()
        #expect(m.objects.count == 4)
        #expect(m.selection.isEmpty || m.selection.allSatisfy { m.document.index(of: $0) != nil })
    }

    @Test func optionChangeRestylesSelectionOrSetsDefault() {
        let m = threeRects()
        m.clearSelection()
        m.setTool(.rectangle)
        m.changeOption("Colour") { $0.color = .blue }
        #expect(m.settings(for: .rectangle).color == .blue)
        #expect(m.objects.allSatisfy { $0.style.color == .red }) // nothing selected: default only
        m.select([m.objects[1].id])
        m.changeOption("Colour") { $0.color = .green }
        #expect(m.objects[1].style.color == .green)
        #expect(m.objects[0].style.color == .red)
        m.store.undo()
        #expect(m.objects[1].style.color == .red)
    }

    @Test func toolSettingsPersistAcrossLibraries() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        let a = ToolSettingsLibrary(defaults: defaults)
        a.update(.pen) { $0.thicknessStep = 4; $0.color = .purple }
        a.lastTool = .counter
        let b = ToolSettingsLibrary(defaults: defaults)
        #expect(b.settings(for: .pen).thicknessStep == 4)
        #expect(b.settings(for: .pen).color == .purple)
        #expect(b.lastTool == .counter)
        #expect(b.settings(for: .highlighter).color == .yellow) // per-tool defaults
    }

    @Test func settingsRoundTripFromObject() {
        let m = makeModel(size: CGSize(width: 5120, height: 2880))
        m.library.update(.text) { $0.sizeStep = 4; $0.thicknessStep = 3 }
        let style = m.style(for: .text)
        let object = AnnotationObject(shape: .text(TextBox(origin: .zero, string: "x")), style: style)
        let s = ToolSettings.from(object, pixelSize: m.document.pixelSize, scale: 2, base: ToolSettings())
        #expect(s.sizeStep == 4)
        #expect(s.thicknessStep == 3)
    }
}

@MainActor
struct KeyHandlerTests {
    @Test func escapeDeselectsThenSwitchesToSelectAndNeverCloses() {
        let m = makeModel(tool: .rectangle)
        let keys = EditorKeyHandler(model: m)
        m.drag(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 100))
        #expect(!m.selection.isEmpty)
        #expect(keys.handle(.escape))
        #expect(m.selection.isEmpty)
        #expect(m.toolKind == .rectangle)
        #expect(keys.handle(.escape))
        #expect(m.toolKind == .select)
        #expect(keys.handle(.escape))
    }

    @Test func toolKeysColoursAndArrowCycle() {
        let m = makeModel()
        let keys = EditorKeyHandler(model: m)
        for kind in ToolKind.allCases {
            #expect(keys.handle(.character(kind.key)))
            #expect(m.toolKind == kind)
        }
        _ = keys.handle(.character("a"))
        let before = m.settings(for: .arrow).arrowStyle
        _ = keys.handle(.character("a"))
        #expect(m.settings(for: .arrow).arrowStyle == before.next)
        _ = keys.handle(.character("5"))
        #expect(m.settings(for: .arrow).color == RGBAColor.presets[4])
        var toggled = false
        keys.onToggleBackground = { toggled = true }
        _ = keys.handle(.character("G"))
        #expect(toggled)
    }

    @Test func arrowsNudgeAndDeleteRemoves() {
        let m = makeModel(tool: .rectangle)
        let keys = EditorKeyHandler(model: m)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        #expect(keys.handle(.arrow(dx: 1, dy: 0)))
        #expect(keys.handle(.arrow(dx: 0, dy: 1), shift: true))
        #expect(rect(of: m.objects[0])?.origin == CGPoint(x: 101, y: 110))
        #expect(keys.handle(.delete))
        #expect(m.objects.isEmpty)
        #expect(!keys.handle(.delete)) // nothing selected: not handled
    }

    @Test func returnEditsSelectedText() {
        let m = makeModel()
        let host = FakeTextHost()
        m.textHost = host
        let text = AnnotationObject(shape: .text(TextBox(origin: .zero, string: "Hi")), style: m.style(for: .text))
        m.store.perform("Add") { $0.objects.append(text) }
        m.select([text.id])
        #expect(EditorKeyHandler(model: m).handle(.returnKey))
        #expect(host.began.count == 1)
    }
}

@MainActor
struct RedactionHintTests {
    @Test func outlinesWithRedactToolOrOnHoverOnly() {
        let m = makeModel(tool: .redact)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        let id = m.objects[0].id
        m.clearSelection()
        #expect(m.redactionHintIDs == [id]) // redact tool: all redactions
        m.select([id])
        #expect(m.redactionHintIDs.isEmpty) // selected: the selection outline is enough
        m.clearSelection()
        m.setTool(.select)
        #expect(m.redactionHintIDs.isEmpty)
        m.hoveredObjectID = id
        #expect(m.redactionHintIDs == [id])
        // Other objects never get a hint.
        m.setTool(.rectangle)
        m.drag(CGPoint(x: 500, y: 500), CGPoint(x: 600, y: 600))
        m.hoveredObjectID = m.objects[1].id
        #expect(m.redactionHintIDs.isEmpty)
    }
}
