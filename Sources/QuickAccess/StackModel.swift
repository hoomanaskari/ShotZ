import Foundation

/// Card order and eviction, independent of views (pure; unit-tested).
///
/// Entries are kept oldest first. Each entry belongs to a group (the display
/// its stack is on), resolved by the caller so it can change when displays or
/// settings change without losing cards.
struct StackModel<ID: Hashable> {
    private(set) var order: [ID] = []

    var isEmpty: Bool { order.isEmpty }
    var count: Int { order.count }

    func contains(_ id: ID) -> Bool { order.contains(id) }

    /// Appends `id` as the newest card (moving it if already present) and
    /// returns the cards evicted from its group because it exceeded `limit`.
    @discardableResult
    mutating func insert(_ id: ID, limit: Int, group: (ID) -> AnyHashable) -> [ID] {
        order.removeAll { $0 == id }
        order.append(id)
        let g = group(id)
        let members = order.filter { group($0) == g }
        guard members.count > limit else { return [] }
        let evicted = Array(members.prefix(members.count - limit))
        order.removeAll { evicted.contains($0) }
        return evicted
    }

    mutating func remove(_ id: ID) {
        order.removeAll { $0 == id }
    }

    mutating func removeAll() { order.removeAll() }

    /// Members of each group, newest first.
    func grouped(by group: (ID) -> AnyHashable) -> [AnyHashable: [ID]] {
        var out: [AnyHashable: [ID]] = [:]
        for id in order.reversed() { out[group(id), default: []].append(id) }
        return out
    }
}
