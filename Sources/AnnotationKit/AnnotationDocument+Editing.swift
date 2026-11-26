import CoreGraphics
import Foundation

/// Pure document mutations for the editor. Use them inside `DocumentStore.perform` so each is
/// one undo step, e.g. `store.perform("Delete") { $0.removeObjects(selection) }`.
extension AnnotationDocument {
    // MARK: Counters
    //
    // Counters form ONE sequence per document regardless of numbering style: `numbering` only
    // changes the label (value 3 shows as "3" or "C"). So 1, 2 then switching to letters gives C,
    // and deleting a counter closes the gap across both styles. This keeps a step list
    // consistent when the user changes the style of some badges after placing them.

    /// The value the next counter should get: one past the highest existing counter of any
    /// numbering style, or `start` when there are none.
    public func nextCounterValue(start: Int = 1) -> Int {
        let values = objects.compactMap { o -> Int? in
            if case .counter(let c) = o.shape { return c.value }
            return nil
        }
        return values.max().map { $0 + 1 } ?? max(start, 1)
    }

    /// Removes objects. Counters above a deleted counter's value shift down by one per deleted
    /// counter, so a 1-2-3 sequence with 2 deleted becomes 1-2 (SPEC §5.3). Typed-over values
    /// keep their relative order.
    public mutating func removeObjects(_ ids: Set<AnnotationObject.ID>) {
        let removedValues = objects.compactMap { o -> Int? in
            guard ids.contains(o.id), case .counter(let c) = o.shape else { return nil }
            return c.value
        }
        objects.removeAll { ids.contains($0.id) }
        guard !removedValues.isEmpty else { return }
        for i in objects.indices {
            guard case .counter(var c) = objects[i].shape else { continue }
            let below = removedValues.filter { $0 < c.value }.count
            if below > 0 {
                c.value -= below
                objects[i].shape = .counter(c)
            }
        }
    }

    /// Renumbers every counter consecutively in z-order (back to front), starting from `start`.
    public mutating func renumberCounters(start: Int = 1) {
        var next = max(start, 1)
        for i in objects.indices {
            guard case .counter(var c) = objects[i].shape else { continue }
            c.value = next
            next += 1
            objects[i].shape = .counter(c)
        }
    }

    // MARK: Z-order (⌘] ⌘[ ⌥⌘] ⌥⌘[)

    /// Moves each selected object one step up, past the next unselected object.
    public mutating func bringForward(_ ids: Set<AnnotationObject.ID>) {
        guard objects.count > 1 else { return }
        for i in stride(from: objects.count - 2, through: 0, by: -1)
            where ids.contains(objects[i].id) && !ids.contains(objects[i + 1].id) {
            objects.swapAt(i, i + 1)
        }
    }

    public mutating func sendBackward(_ ids: Set<AnnotationObject.ID>) {
        guard objects.count > 1 else { return }
        for i in 1..<objects.count where ids.contains(objects[i].id) && !ids.contains(objects[i - 1].id) {
            objects.swapAt(i, i - 1)
        }
    }

    public mutating func bringToFront(_ ids: Set<AnnotationObject.ID>) {
        let moving = objects.filter { ids.contains($0.id) }
        objects.removeAll { ids.contains($0.id) }
        objects.append(contentsOf: moving)
    }

    public mutating func sendToBack(_ ids: Set<AnnotationObject.ID>) {
        let moving = objects.filter { ids.contains($0.id) }
        objects.removeAll { ids.contains($0.id) }
        objects.insert(contentsOf: moving, at: 0)
    }

    // MARK: Duplicate / paste

    /// The selected objects in z-order (what ⌘C copies).
    public func objects(withIDs ids: Set<AnnotationObject.ID>) -> [AnnotationObject] {
        objects.filter { ids.contains($0.id) }
    }

    /// Duplicates the objects (⌘D, ⌥-drag) on top of everything, offset by `offset`.
    /// Returns the new ids (the new selection). Duplicated counters take the next values.
    @discardableResult
    public mutating func duplicate(_ ids: Set<AnnotationObject.ID>, offset: CGVector) -> [AnnotationObject.ID] {
        insert(objects(withIDs: ids), offset: offset)
    }

    /// Pastes copies of `pasted` (fresh ids) on top, offset by `offset`. Returns the new ids.
    @discardableResult
    public mutating func paste(_ pasted: [AnnotationObject], offset: CGVector) -> [AnnotationObject.ID] {
        insert(pasted, offset: offset)
    }

    private mutating func insert(_ source: [AnnotationObject], offset: CGVector) -> [AnnotationObject.ID] {
        var next = nextCounterValue()
        let copies = source.map { o -> AnnotationObject in
            var copy = o.duplicated(offsetBy: offset)
            if case .counter(var c) = copy.shape {
                c.value = next
                next += 1
                copy.shape = .counter(c)
            }
            return copy
        }
        objects.append(contentsOf: copies)
        return copies.map(\.id)
    }

    /// The diagonal step for ⌘D and repeated pastes, scaled to the image.
    public var defaultPasteOffset: CGVector {
        let step = (ObjectStyle.thicknessUnit(for: pixelSize) * 5).rounded()
        return CGVector(dx: step, dy: step)
    }
}

/// Clipboard format for objects copied between editor windows (⌘C / ⌘V).
public enum AnnotationPasteboard {
    /// UTI-style pasteboard type string for `NSPasteboard.PasteboardType(rawValue:)`.
    public static let typeIdentifier = "com.pixelforty.shotz.annotation-objects"

    private struct Payload: Codable {
        var version = 1
        var objects: [AnnotationObject]
    }

    public static func encode(_ objects: [AnnotationObject]) throws -> Data {
        try JSONEncoder().encode(Payload(objects: objects))
    }

    /// Objects from pasteboard data; unknown or damaged entries are skipped.
    public static func decode(_ data: Data) -> [AnnotationObject] {
        guard let payload = try? JSONDecoder().decode(LossyObjects.self, from: data) else { return [] } // foreign data: nothing to paste
        return payload.objects
    }

    private struct LossyObjects: Decodable {
        var objects: [AnnotationObject]
        enum CodingKeys: String, CodingKey { case objects }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            objects = try c.decode(LossyArray<AnnotationObject>.self, forKey: .objects).elements
        }
    }
}
