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

    @Test func startValueAndTypedValue() {
        let m = makeModel(tool: .counter)
        m.library.update(.counter) { $0.counterStart = 5 }
        m.click(CGPoint(x: 100, y: 100))
        #expect(values(m) == [5])
        let keys = EditorKeyHandler(model: m)
        var t = Date()
        keys.now = { t }
        _ = keys.handle(.character("1"))
        t += 0.2
        _ = keys.handle(.character("2"))
        #expect(values(m) == [12])
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
