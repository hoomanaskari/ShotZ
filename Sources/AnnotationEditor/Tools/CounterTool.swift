import AnnotationKit
import CoreGraphics

/// N: each click drops the next number; dragging while placing pulls out a
/// pointer tail. A plain click on an existing counter selects it.
@MainActor final class CounterTool: DrawingTool {
    init() { super.init(kind: .counter) }

    override func createsOnMouseDown() -> Bool { true }

    override func selectsOnClick(_ object: AnnotationObject) -> Bool {
        if case .counter = object.shape { return true }
        return false
    }

    override func makeShape(from start: CGPoint, to current: CGPoint, modifiers: ToolModifiers) -> AnnotationObject.Shape? {
        guard let model else { return nil }
        let s = model.settings(for: .counter)
        // The value is fixed when the counter is first placed.
        var value = CounterNumberingShim.nextValue(in: model.document, numbering: s.counterNumbering, start: s.counterStart)
        if let id = creatingID, let existing = model.document[id: id], case .counter(let c) = existing.shape {
            value = c.value
        }
        let distance = hypot(current.x - start.x, current.y - start.y)
        let radius = style().fontSize
        let tail: CGPoint? = distance > max(radius, model.dragThreshold) ? current : nil
        return .counter(CounterGeometry(center: start, tail: tail, value: value, numbering: s.counterNumbering))
    }
}
