import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

@MainActor
struct EditingTests {
    func counter(_ v: Int) -> AnnotationObject {
        AnnotationObject(shape: .counter(CounterGeometry(center: CGPoint(x: v * 10, y: 0), value: v)))
    }
    func values(_ d: AnnotationDocument) -> [Int] {
        d.objects.compactMap { if case .counter(let c) = $0.shape { c.value } else { nil } }
    }
    func doc(_ objects: [AnnotationObject]) -> AnnotationDocument {
        AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: CGSize(width: 800, height: 400), objects: objects)
    }

    @Test func deletingCountersRenumbers() {
        let cs = (1...5).map(counter)
        var d = doc(cs)
        d.removeObjects([cs[1].id, cs[3].id])
        #expect(values(d) == [1, 2, 3])
        #expect(d.nextCounterValue() == 4)
        #expect(doc([]).nextCounterValue(start: 5) == 5)
        var e = doc([counter(7), counter(3)])
        e.renumberCounters()
        #expect(values(e) == [1, 2])
    }

    @Test func zOrder() {
        let (a, b, c, d) = (counter(1), counter(2), counter(3), counter(4))
        var doc = doc([a, b, c, d])
        doc.bringForward([a.id])
        #expect(doc.objects.map(\.id) == [b.id, a.id, c.id, d.id])
        doc.bringToFront([b.id])
        #expect(doc.objects.map(\.id) == [a.id, c.id, d.id, b.id])
        doc.sendBackward([d.id, b.id])
        #expect(doc.objects.map(\.id) == [a.id, d.id, b.id, c.id])
        doc.sendToBack([c.id])
        #expect(doc.objects.map(\.id) == [c.id, a.id, d.id, b.id])
        doc.bringForward([b.id]) // already at front: no-op
        #expect(doc.objects.last?.id == b.id)
    }

    @Test func duplicateAndPasteGetFreshIDsAndNextCounters() throws {
        let rect = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        var d = doc([rect, counter(1)])
        let ids = d.duplicate([rect.id, d.objects[1].id], offset: CGVector(dx: 5, dy: 5))
        #expect(ids.count == 2 && !ids.contains(rect.id))
        #expect(d.objects[2].shape == .rectangle(CGRect(x: 5, y: 5, width: 10, height: 10), cornerRadius: 0))
        #expect(values(d) == [1, 2])
        let data = try AnnotationPasteboard.encode(d.objects(withIDs: Set(ids)))
        let decoded = AnnotationPasteboard.decode(data)
        #expect(decoded.count == 2)
        let pasted = d.paste(decoded, offset: .zero)
        #expect(Set(pasted).isDisjoint(with: Set(ids)))
        #expect(values(d) == [1, 2, 3])
        #expect(AnnotationPasteboard.decode(Data("nope".utf8)).isEmpty)
    }

    @Test func editsThroughStoreUndoAsOneStep() {
        let cs = (1...3).map(counter)
        let store = DocumentStore(document: doc(cs))
        store.perform("Delete") { $0.removeObjects([cs[0].id]) }
        #expect(values(store.document) == [1, 2])
        store.undo()
        #expect(store.document.objects == cs)
        store.redo()
        #expect(values(store.document) == [1, 2])
        // A resize drag is one undo step.
        let box = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 0))
        store.perform("Add") { $0.objects.append(box) }
        store.beginInteractiveChange("Resize")
        for x in stride(from: 12, through: 40, by: 4) {
            store.updateInteractive { $0[id: box.id] = ObjectGeometry.resized(box, handle: .bottomRight, to: CGPoint(x: x, y: x)) }
        }
        store.commitInteractiveChange()
        #expect(store.document[id: box.id]?.shape == .rectangle(CGRect(x: 0, y: 0, width: 40, height: 40), cornerRadius: 0))
        store.undo()
        #expect(store.document[id: box.id] == box)
    }

    @Test func defaultStylesScaleWithImage() {
        let small = ObjectStyle.defaultStyle(for: .arrow, pixelSize: CGSize(width: 1440, height: 900), scale: 1)
        let big = ObjectStyle.defaultStyle(for: .arrow, pixelSize: CGSize(width: 5120, height: 2880), scale: 2)
        #expect(abs(big.lineWidth / small.lineWidth - 5120.0 / 1440) < 0.2)
        #expect(ObjectStyle.defaultStyle(for: .highlighter, pixelSize: CGSize(width: 800, height: 600)).color == .yellow)
        #expect(ObjectStyle.defaultStyle(for: .counter, pixelSize: CGSize(width: 2000, height: 1000)).fontSize >= 8)
        let w = ObjectStyle.lineWidth(step: 3, pixelSize: CGSize(width: 4000, height: 3000))
        #expect(ObjectStyle.thicknessStep(forLineWidth: w, pixelSize: CGSize(width: 4000, height: 3000)) == 3)
        #expect(AnnotationObject(shape: .pen([])).kind == .pen)
    }
}
