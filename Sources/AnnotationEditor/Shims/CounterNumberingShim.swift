import AnnotationKit

// TEMP until AnnotationKit provides counter numbering.
// Pure; unit-tested.
enum CounterNumberingShim {
    /// The value the next counter of `numbering` gets.
    static func nextValue(in document: AnnotationDocument, numbering: CounterGeometry.Numbering, start: Int) -> Int {
        let values = document.objects.compactMap { object -> Int? in
            if case .counter(let c) = object.shape, c.numbering == numbering { return c.value }
            return nil
        }
        return values.max().map { $0 + 1 } ?? start
    }

    /// Removes `ids` and closes the gaps they leave: every remaining counter
    /// of the same numbering with a higher value moves down by one per removed counter.
    static func remove(_ ids: Set<AnnotationObject.ID>, from document: inout AnnotationDocument) {
        let removedCounters = document.objects.compactMap { object -> CounterGeometry? in
            guard ids.contains(object.id), case .counter(let c) = object.shape else { return nil }
            return c
        }
        document.objects.removeAll { ids.contains($0.id) }
        guard !removedCounters.isEmpty else { return }
        for i in document.objects.indices {
            guard case .counter(var c) = document.objects[i].shape else { continue }
            let below = removedCounters.filter { $0.numbering == c.numbering && $0.value < c.value }.count
            guard below > 0 else { continue }
            c.value = max(1, c.value - below)
            document.objects[i].shape = .counter(c)
        }
    }
}
