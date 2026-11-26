import AnnotationKit
import CoreGraphics
import Foundation
import Testing
@testable import AnnotationEditor

@MainActor
struct CounterToolTests {
    private func values(_ m: EditorModel) -> [Int] {
        m.objects.compactMap { if case .counter(let c) = $0.shape { return c.value } else { return nil } }
    }

    @Test func clicksNumberAndDeleteRenumbers() {
        let m = makeModel(tool: .counter)
        m.click(CGPoint(x: 100, y: 100))
        m.click(CGPoint(x: 300, y: 100))
        m.click(CGPoint(x: 500, y: 100))
        #expect(values(m) == [1, 2, 3])
        m.select([m.objects[0].id])
        m.deleteSelection()
        #expect(values(m) == [1, 2])
        m.store.undo()
        #expect(values(m) == [1, 2, 3])
    }

    @Test func dragPullsATail() throws {
        let m = makeModel(tool: .counter)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 400, y: 300))
        guard case .counter(let c) = try #require(m.objects.first).shape else { Issue.record("not a counter"); return }
        #expect(c.center == CGPoint(x: 100, y: 100))
        #expect(c.tail == CGPoint(x: 400, y: 300))
        #expect(m.store.undoActionName != nil)
    }

    @Test func clickOnExistingCounterSelectsInsteadOfAdding() {
        let m = makeModel(tool: .counter)
        m.click(CGPoint(x: 100, y: 100))
        m.clearSelection()
        m.click(CGPoint(x: 102, y: 101))
        #expect(m.objects.count == 1)
        #expect(m.selection == [m.objects[0].id])
    }

    @Test func startValue() {
        let m = makeModel(tool: .counter)
        m.library.update(.counter) { $0.counterStart = 5 }
        m.click(CGPoint(x: 100, y: 100))
        #expect(values(m) == [5])
    }

    @Test func digitsPickColoursUntilValueEditingStarts() {
        let m = makeModel(tool: .counter)
        m.click(CGPoint(x: 100, y: 100))
        let keys = EditorKeyHandler(model: m)
        // A selected counter: 5 picks blue, it does not change the number.
        #expect(keys.handle(.character("5")))
        #expect(values(m) == [1])
        #expect(m.objects[0].style.color == RGBAColor.presets[4])
        // Return enters value editing; digits replace the number; Return commits in one step.
        #expect(keys.handle(.returnKey))
        #expect(m.editingCounterID == m.objects[0].id)
        _ = keys.handle(.character("1"))
        _ = keys.handle(.character("2"))
        #expect(values(m) == [12])
        _ = keys.handle(.delete)
        #expect(values(m) == [1])
        _ = keys.handle(.character("7"))
        _ = keys.handle(.returnKey)
        #expect(m.editingCounterID == nil)
        #expect(values(m) == [17])
        m.store.undo()
        #expect(values(m) == [1])
        #expect(m.objects[0].style.color == RGBAColor.presets[4]) // the colour change was its own step
    }

    @Test func escCancelsValueEditingAndDoubleClickStartsIt() {
        let m = makeModel(tool: .counter)
        m.click(CGPoint(x: 100, y: 100))
        m.setTool(.select)
        m.click(CGPoint(x: 100, y: 100), count: 2)
        #expect(m.editingCounterID == m.objects[0].id)
        let keys = EditorKeyHandler(model: m)
        _ = keys.handle(.character("9"))
        #expect(values(m) == [9])
        #expect(keys.handle(.escape))
        #expect(m.editingCounterID == nil)
        #expect(values(m) == [1])
        #expect(!m.selection.isEmpty) // Esc ended the edit only
    }

    @Test func clickingAnotherObjectEndsValueEditing() {
        let m = makeModel(tool: .counter)
        m.click(CGPoint(x: 100, y: 100))
        m.click(CGPoint(x: 400, y: 100))
        m.beginCounterValueEditing(m.objects[0].id)
        m.typeCounterDigit(4)
        m.select([m.objects[1].id])
        #expect(m.editingCounterID == nil)
        #expect(values(m) == [4, 2])
    }

    @Test func counterToolClickOnAnyObjectSelectsIt() {
        let m = makeModel(tool: .rectangle)
        m.library.update(.rectangle) { $0.fill = .filled }
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
        m.setTool(.counter)
        m.clearSelection()
        m.click(CGPoint(x: 200, y: 200))
        #expect(m.objects.count == 1)
        #expect(m.selection == [m.objects[0].id])
        // A drag that starts on an unselected object still places a counter with a tail
        // (dragging a selected object moves it).
        m.clearSelection()
        m.drag(CGPoint(x: 200, y: 200), CGPoint(x: 500, y: 450))
        #expect(m.objects.count == 2)
    }
}

@MainActor
struct TextToolTests {
    @Test func clickPlacesNewTextAndEmptyIsDiscarded() throws {
        let m = makeModel(tool: .text)
        let host = FakeTextHost()
        m.textHost = host
        m.click(CGPoint(x: 200, y: 200))
        let (draft, isNew) = try #require(host.began.first)
        #expect(isNew)
        #expect(m.objects.isEmpty) // not in the document until committed
        m.commitText(draft, string: "   ", isNew: true)
        #expect(m.objects.isEmpty)
        #expect(!m.store.canUndo)
    }

    @Test func commitAddsInOneStepAndEditsInAnother() throws {
        let m = makeModel(tool: .text)
        let host = FakeTextHost()
        m.textHost = host
        m.click(CGPoint(x: 200, y: 200))
        let draft = try #require(host.began.first?.0)
        m.commitText(draft, string: "Hello", isNew: true)
        #expect(m.objects.count == 1)
        let added = m.objects[0]
        m.commitText(added, string: "Hello there", isNew: false)
        guard case .text(let box) = m.objects[0].shape else { Issue.record("not text"); return }
        #expect(box.string == "Hello there")
        m.commitText(m.objects[0], string: "", isNew: false)
        #expect(m.objects.isEmpty) // emptied text is deleted
        m.store.undo(); m.store.undo()
        guard case .text(let original) = m.objects[0].shape else { Issue.record("not text"); return }
        #expect(original.string == "Hello")
    }

    @Test func plainClickSelectsAnyObjectAndDoubleClickEditsText() throws {
        let m = makeModel(tool: .rectangle)
        m.library.update(.rectangle) { $0.fill = .filled }
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
        let text = AnnotationObject(shape: .text(TextBox(origin: CGPoint(x: 600, y: 100), string: "Hi")), style: m.style(for: .text))
        m.store.perform("Add") { $0.objects.append(text) }
        m.setTool(.text)
        let host = FakeTextHost()
        m.textHost = host
        m.click(CGPoint(x: 200, y: 200))
        #expect(m.selection == [m.objects[0].id])
        #expect(host.began.isEmpty)
        m.click(CGPoint(x: 610, y: 110))
        #expect(m.selection == [text.id])
        #expect(host.began.isEmpty) // a plain click selects
        m.click(CGPoint(x: 610, y: 110), count: 2)
        #expect(host.began.first?.0.id == text.id)
        #expect(host.began.first?.1 == false)
    }

    @Test func dragSetsWrapWidth() throws {
        let m = makeModel(tool: .text)
        let host = FakeTextHost()
        m.textHost = host
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 500, y: 140))
        guard case .text(let box) = try #require(host.began.first?.0).shape else { Issue.record("not text"); return }
        #expect(box.wrapWidth == 400)
    }
}

@MainActor
struct CropToolTests {
    @Test func dragThenReturnAppliesAndEscCancels() {
        let m = makeModel(tool: .crop)
        #expect(m.cropDraft == m.imageBounds)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 900, y: 600))
        #expect(m.cropDraft == CGRect(x: 100, y: 100, width: 800, height: 500))
        #expect(m.tool.keyDown(.returnKey))
        #expect(m.document.crop == CGRect(x: 100, y: 100, width: 800, height: 500))
        #expect(m.toolKind == .select)

        // Re-open: the draft starts from the crop and can be widened back to full.
        m.setTool(.crop)
        #expect(m.cropDraft == m.document.crop)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 0, y: 0)) // top-left handle
        #expect(m.tool.keyDown(.escape))
        #expect(m.document.crop == CGRect(x: 100, y: 100, width: 800, height: 500))
    }

    @Test func fullImageCropIsNil() {
        let m = makeModel(tool: .crop)
        m.store.perform("Crop") { $0.crop = CGRect(x: 10, y: 10, width: 100, height: 100) }
        m.setTool(.crop)
        m.cropDraft = m.imageBounds
        (m.tool as? CropTool)?.apply()
        #expect(m.document.crop == nil)
    }

    @Test func aspectPresetsAndNumericSize() throws {
        let m = makeModel(tool: .crop)
        let crop = try #require(m.tool as? CropTool)
        m.cropAspect = .square
        crop.applyAspect()
        #expect(m.cropDraft?.width == m.cropDraft?.height)
        crop.setSize(width: 400, height: nil)
        #expect(m.cropDraft?.size == CGSize(width: 400, height: 400))
        m.cropAspect = .free
        crop.setSize(width: nil, height: 250)
        #expect(m.cropDraft?.size == CGSize(width: 400, height: 250))
        crop.setSize(width: 99_999, height: nil)
        #expect(m.cropDraft?.width == 1600) // clamped to the image
    }
}
