import CoreGraphics
import Testing
@testable import QuickAccess
import ShotzCore

struct StackLayoutTests {
    let visible = CGRect(x: 0, y: 74, width: 2560, height: 1336)
    let large = CGSize(width: 250, height: 156.25)

    @Test func leftColumnGeometry() {
        let l = StackLayout(visibleFrame: visible, side: .left, cardSize: large)
        #expect(l.cardSize == CGSize(width: 250, height: 156))
        #expect(l.capacity == 5)
        #expect(l.panelFrame == CGRect(x: 0, y: 74, width: 16 + 250 + 16, height: 16 + 5 * 156 + 4 * 10 + 16))
        #expect(l.cardFrame(slot: 0) == CGRect(x: 16, y: 16, width: 250, height: 156))
        #expect(l.cardFrame(slot: 1) == CGRect(x: 16, y: 182, width: 250, height: 156))
        #expect(l.entranceFrame(slot: 0).maxX < 0)
        #expect(l.entranceFrame(slot: 2).minY == l.cardFrame(slot: 2).minY)
    }

    @Test func rightColumnHugsRightEdge() {
        let l = StackLayout(visibleFrame: visible, side: .right, cardSize: large)
        #expect(l.panelFrame.maxX == visible.maxX)
        // Card's right edge is inset 16 from the screen edge.
        #expect(l.panelFrame.minX + l.cardFrame(slot: 0).maxX == visible.maxX - 16)
        #expect(l.entranceFrame(slot: 0).minX > l.panelFrame.width)
    }

    @Test func shortDisplayHoldsFewerCards() {
        let short = CGRect(x: 100, y: 0, width: 800, height: 400)
        let l = StackLayout(visibleFrame: short, side: .left, cardSize: large)
        #expect(l.capacity == 2)
        #expect(l.slots(count: 4) == [0, 1, nil, nil])
        #expect(l.panelFrame.height <= short.height)
        #expect(l.panelFrame.minX == 100)
        let tiny = StackLayout(visibleFrame: CGRect(x: 0, y: 0, width: 300, height: 50), side: .left, cardSize: large)
        #expect(tiny.capacity == 1)
    }

    @Test func slotsCapAtFive() {
        let l = StackLayout(visibleFrame: visible, side: .left, cardSize: CGSize(width: 150, height: 93.75))
        #expect(l.capacity == 5)
        #expect(l.slots(count: 7) == [0, 1, 2, 3, 4, nil, nil])
    }

    @Test func swipeEdge() {
        let screen = CGRect(x: 0, y: 0, width: 2560, height: 1440)
        let left = StackLayout(visibleFrame: visible, side: .left, cardSize: large)
        #expect(left.isAtEdge(CGPoint(x: 0, y: 300), screenFrame: screen))
        #expect(left.isAtEdge(CGPoint(x: 3, y: 300), screenFrame: screen))
        #expect(!left.isAtEdge(CGPoint(x: 40, y: 300), screenFrame: screen))
        #expect(!left.isAtEdge(CGPoint(x: -500, y: 300), screenFrame: screen)) // far onto a neighbouring display
        #expect(!left.isAtEdge(CGPoint(x: 0, y: 2000), screenFrame: screen))
        let right = StackLayout(visibleFrame: visible, side: .right, cardSize: large)
        #expect(right.isAtEdge(CGPoint(x: 2559, y: 300), screenFrame: screen))
        #expect(!right.isAtEdge(CGPoint(x: 0, y: 300), screenFrame: screen))
    }
}

struct StackModelTests {
    @Test func newestLastAndEvictionPerGroup() {
        var m = StackModel<Int>()
        let group: (Int) -> AnyHashable = { $0 >= 100 ? "B" : "A" }
        for i in 1...5 { #expect(m.insert(i, limit: 5, group: group).isEmpty) }
        #expect(m.insert(100, limit: 5, group: group).isEmpty) // other display, no eviction
        #expect(m.insert(6, limit: 5, group: group) == [1])
        #expect(m.order == [2, 3, 4, 5, 100, 6])
        #expect(m.grouped(by: group)["A"] == [6, 5, 4, 3, 2])
        #expect(m.grouped(by: group)["B"] == [100])
    }

    @Test func reinsertMovesToNewest() {
        var m = StackModel<Int>()
        for i in 1...3 { m.insert(i, limit: 5) { _ in 0 } }
        m.insert(1, limit: 5) { _ in 0 }
        #expect(m.order == [2, 3, 1])
        m.remove(3)
        #expect(m.order == [2, 1])
    }

    @Test func annotateHideThenReturnIsNewestOnce() {
        var m = StackModel<Int>()
        for i in 1...4 { m.insert(i, limit: 5) { _ in 0 } }
        m.remove(2)                      // Annotate hides card 2
        #expect(m.order == [1, 3, 4])
        m.insert(2, limit: 5) { _ in 0 } // editor closed: back as newest
        #expect(m.order == [1, 3, 4, 2])
        m.insert(2, limit: 5) { _ in 0 } // a second present replaces, never duplicates
        #expect(m.order == [1, 3, 4, 2])
        for _ in 0..<10 {                 // rapid open/close cycles
            m.remove(2)
            m.insert(2, limit: 5) { _ in 0 }
        }
        #expect(m.order.filter { $0 == 2 }.count == 1)
        #expect(m.count == 4)
    }

    @Test func tenRapidInsertsKeepOrder() {
        var m = StackModel<Int>()
        var evicted: [Int] = []
        for i in 1...10 { evicted += m.insert(i, limit: 5) { _ in 0 } }
        #expect(m.order == [6, 7, 8, 9, 10])
        #expect(evicted == [1, 2, 3, 4, 5])
    }
}

struct DisplayChoiceTests {
    @Test func resolves() {
        #expect(DisplayChoice.resolve(captured: 7, setting: .whereCaptured, available: [1, 7], main: 1) == 7)
        #expect(DisplayChoice.resolve(captured: 7, setting: .main, available: [1, 7], main: 1) == 1)
        // Disconnected display: the stack moves to the main one.
        #expect(DisplayChoice.resolve(captured: 9, setting: .whereCaptured, available: [1, 7], main: 1) == 1)
    }
}
