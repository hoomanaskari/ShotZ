import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

@MainActor
struct DocumentStoreTests {
    func makeStore() -> DocumentStore {
        DocumentStore(document: AnnotationDocument(baseImageURL: URL(filePath: "/tmp/base.png"), pixelSize: CGSize(width: 100, height: 80)))
    }

    func rect(_ x: CGFloat) -> AnnotationObject {
        AnnotationObject(shape: .rectangle(CGRect(x: x, y: 0, width: 10, height: 10), cornerRadius: 0))
    }

    @Test func performUndoRedo() {
        let store = makeStore()
        #expect(!store.canUndo && !store.canRedo)
        let obj = rect(1)
        store.perform("Add") { $0.objects.append(obj) }
        #expect(store.document.objects == [obj])
        #expect(store.canUndo)
        #expect(store.undoActionName == "Add")
        store.undo()
        #expect(store.document.objects.isEmpty)
        #expect(store.canRedo)
        store.redo()
        #expect(store.document.objects == [obj])
        #expect(!store.canRedo)
    }

    @Test func noOpIsNotRecorded() {
        let store = makeStore()
        store.perform("Nothing") { _ in }
        #expect(!store.canUndo)
    }

    @Test func newChangeClearsRedo() {
        let store = makeStore()
        store.perform("A") { $0.objects.append(rect(1)) }
        store.undo()
        store.perform("B") { $0.objects.append(rect(2)) }
        #expect(!store.canRedo)
    }

    @Test func interactiveChangeIsOneUndoStep() {
        let store = makeStore()
        let obj = rect(0)
        store.perform("Add") { $0.objects.append(obj) }
        store.beginInteractiveChange("Move")
        for x in 1...5 {
            store.updateInteractive { $0[id: obj.id]?.shape = .rectangle(CGRect(x: CGFloat(x), y: 0, width: 10, height: 10), cornerRadius: 0) }
        }
        store.commitInteractiveChange()
        #expect(store.document[id: obj.id]?.shape == .rectangle(CGRect(x: 5, y: 0, width: 10, height: 10), cornerRadius: 0))
        store.undo()
        #expect(store.document.objects == [obj])
        store.undo()
        #expect(store.document.objects.isEmpty)
        #expect(!store.canUndo)
    }

    @Test func cancelInteractiveRestores() {
        let store = makeStore()
        store.beginInteractiveChange("Crop")
        store.updateInteractive { $0.crop = CGRect(x: 0, y: 0, width: 5, height: 5) }
        store.cancelInteractiveChange()
        #expect(store.document.crop == nil)
        #expect(!store.canUndo)
    }

    @Test func emptyInteractiveNotRecorded() {
        let store = makeStore()
        store.beginInteractiveChange("Drag")
        store.commitInteractiveChange()
        #expect(!store.canUndo)
    }

    @Test func changesStreamReportsIDs() async {
        let store = makeStore()
        let stream = store.changes
        let obj = rect(1)
        store.perform("Add") { $0.objects.append(obj) }
        store.perform("Style") { $0[id: obj.id]?.style.color = .blue }
        store.undo()
        var iterator = stream.makeAsyncIterator()
        let added = await iterator.next()
        let modified = await iterator.next()
        let undone = await iterator.next()
        #expect(added?.added == [obj.id])
        #expect(added?.reason == .perform("Add"))
        #expect(modified?.modified == [obj.id])
        #expect(undone?.reason == .undo)
        #expect(undone?.modified == [obj.id])
    }
}
