import AnnotationKit
import CoreGraphics
import Testing
@testable import AnnotationEditor

@MainActor
struct SelectToolTests {
    /// Two filled rectangles (hit anywhere inside).
    private func twoRects() -> EditorModel {
        let m = makeModel(tool: .rectangle)
        m.library.update(.rectangle) { $0.fill = .filled }
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 200, y: 200))
        m.drag(CGPoint(x: 400, y: 100), CGPoint(x: 500, y: 200))
        m.setTool(.select)
        m.clearSelection()
        return m
    }

    @Test func clickShiftClickAndMarquee() {
        let m = twoRects()
        let (a, b) = (m.objects[0].id, m.objects[1].id)
        m.click(CGPoint(x: 150, y: 150))
        #expect(m.selection == [a])
        m.click(CGPoint(x: 450, y: 150), [.shift])
        #expect(m.selection == [a, b])
        m.click(CGPoint(x: 450, y: 150), [.shift])
        #expect(m.selection == [a])
        m.click(CGPoint(x: 900, y: 900))
        #expect(m.selection.isEmpty)
        m.drag(CGPoint(x: 50, y: 50), CGPoint(x: 600, y: 300))
        #expect(Set(m.selection) == [a, b])
        #expect(m.marquee == nil)
    }

    @Test func dragMovesInOneUndoStepAndShiftConstrains() throws {
        let m = twoRects()
        m.drag(CGPoint(x: 150, y: 150), CGPoint(x: 180, y: 160))
        #expect(rect(of: m.objects[0]) == CGRect(x: 130, y: 110, width: 100, height: 100))
        // ⇧ pressed after mouse-down constrains to an axis (⇧ at mouse-down is a ⇧-click).
        m.tool.mouseDown(ToolEvent(CGPoint(x: 180, y: 160)))
        m.tool.mouseDragged(ToolEvent(CGPoint(x: 230, y: 175), [.shift]))
        m.tool.mouseUp(ToolEvent(CGPoint(x: 230, y: 175), [.shift]))
        #expect(rect(of: m.objects[0]) == CGRect(x: 180, y: 110, width: 100, height: 100))
        m.store.undo()
        #expect(rect(of: m.objects[0]) == CGRect(x: 130, y: 110, width: 100, height: 100))
    }

    @Test func optionDragDuplicates() {
        let m = twoRects()
        m.drag(CGPoint(x: 150, y: 150), CGPoint(x: 150, y: 450), [.option])
        #expect(m.objects.count == 3)
        #expect(rect(of: m.objects[0]) == CGRect(x: 100, y: 100, width: 100, height: 100))
        #expect(rect(of: m.objects[2]) == CGRect(x: 100, y: 400, width: 100, height: 100))
        #expect(m.selection == [m.objects[2].id])
        m.store.undo()
        #expect(m.objects.count == 2)
    }

    @Test func handleResizes() {
        let m = twoRects()
        m.click(CGPoint(x: 150, y: 150))
        m.drag(CGPoint(x: 200, y: 200), CGPoint(x: 260, y: 230))
        #expect(rect(of: m.objects[0]) == CGRect(x: 100, y: 100, width: 160, height: 130))
    }

    @Test func clickWithoutMovingChangesNothing() {
        let m = twoRects()
        m.click(CGPoint(x: 150, y: 150))
        #expect(m.store.undoActionName == String(localized: "Add Rectangle"))
    }

    @Test func snappingAlignsEdgesAndShowsGuides() {
        let m = twoRects()
        m.snappingSetting = { true }
        m.click(CGPoint(x: 450, y: 150))
        // Move the second rect so its top is 3 px below the first's: it snaps flush.
        m.tool.mouseDown(ToolEvent(CGPoint(x: 450, y: 150)))
        m.tool.mouseDragged(ToolEvent(CGPoint(x: 450, y: 153)))
        #expect(!m.guides.isEmpty)
        m.tool.mouseUp(ToolEvent(CGPoint(x: 450, y: 153)))
        #expect(rect(of: m.objects[1])?.minY == 100)
        #expect(m.guides.isEmpty)
        // ⌘ disables snapping.
        m.drag(CGPoint(x: 450, y: 150), CGPoint(x: 450, y: 153), [.command])
        #expect(rect(of: m.objects[1])?.minY == 103)
    }

    @Test func doubleClickTextStartsEditing() {
        let m = makeModel()
        let host = FakeTextHost()
        m.textHost = host
        let text = AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 100, y: 100), string: "Hi")), style: m.style(for: .text))
        m.store.perform("Add") { $0.objects.append(text) }
        m.click(CGPoint(x: 110, y: 110), count: 2)
        #expect(host.began.first?.0.id == text.id)
        #expect(host.began.first?.1 == false)
    }
}
