import CoreGraphics

/// Finds the display under the pointer and its `screencapture -D` number.
enum DisplayLocator {
    struct Located: Equatable, Sendable {
        let displayID: CGDirectDisplayID
        /// 1-based, main display first (screencapture's ordering).
        let number: Int
    }

    static func displayUnderPointer() -> Located {
        let main = CGMainDisplayID()
        // Global display coordinates (top-left origin), the space CGGetDisplaysWithPoint uses.
        let pointer = CGEvent(source: nil)?.location ?? .zero
        var count: UInt32 = 0
        var hit = CGDirectDisplayID()
        let found = CGGetDisplaysWithPoint(pointer, 1, &hit, &count) == .success && count > 0
        let target = found ? hit : main
        return Located(displayID: target, number: number(of: target, in: activeDisplays(), main: main))
    }

    static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        return Array(ids.prefix(Int(count)))
    }

    /// Main first, then the others in system order. Unknown displays map to the main one.
    static func number(of display: CGDirectDisplayID, in displays: [CGDirectDisplayID], main: CGDirectDisplayID) -> Int {
        let ordered = [main] + displays.filter { $0 != main }
        return (ordered.firstIndex(of: display) ?? 0) + 1
    }
}
