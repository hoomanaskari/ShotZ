import AnnotationKit
import CoreGraphics
import Testing
@testable import AnnotationEditor

@MainActor
struct DrawingToolTests {
    @Test func rectangleDragCreatesOneObjectInOneUndoStep() {
        let m = makeModel(tool: .rectangle)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 200))
        #expect(m.objects.count == 1)
        #expect(rect(of: m.objects[0]) == CGRect(x: 100, y: 100, width: 200, height: 100))
        #expect(m.selection == [m.objects[0].id])
        #expect(m.toolKind == .rectangle) // stays armed
        m.store.undo()
        #expect(m.objects.isEmpty)
        #expect(!m.store.canUndo)
    }

    @Test func shiftSquaresAndOptionDrawsFromCentre() {
        #expect(ShapeTool.box(CGPoint(x: 0, y: 0), CGPoint(x: 50, y: 20), [.shift]) == CGRect(x: 0, y: 0, width: 50, height: 50))
        #expect(ShapeTool.box(CGPoint(x: 100, y: 100), CGPoint(x: 120, y: 130), [.option]) == CGRect(x: 80, y: 70, width: 40, height: 60))
    }

    @Test func tinyDragCreatesNothing() {
        let m = makeModel(tool: .rectangle)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 101, y: 101))
        #expect(m.objects.isEmpty)
        #expect(!m.store.canUndo)
    }

    @Test func plainClickOnExistingObjectSelectsIt() {
        let m = makeModel(tool: .ellipse)
        m.drag(CGPoint(x: 100, y: 100), CGPoint(x: 300, y: 300))
        m.clearSelection()
        // Click on the outline.
        m.click(CGPoint(x: 100, y: 200))
        #expect(m.objects.count == 1)
        #expect(m.selection == [m.objects[0].id])
    }

    @Test func returnToSelectSetting() {
        let m = makeModel(tool: .line)
        m.returnToSelectSetting = { true }
        m.drag(CGPoint(x: 10, y: 10), CGPoint(x: 200, y: 10))
        #expect(m.toolKind == .select)
    }

    @Test func lineSnapsTo15DegreesWithShift() throws {
        let m = makeModel(tool: .line)
        m.drag(CGPoint(x: 0, y: 0), CGPoint(x: 100, y: 3), [.shift])
        guard case .line(_, let e) = try #require(m.objects.first).shape else { Issue.record("not a line"); return }
        #expect(abs(e.y) < 0.001)
    }

    @Test func curvedArrowGetsAMidpointHandle() throws {
        let m = makeModel(tool: .arrow)
        m.library.update(.arrow) { $0.arrowStyle = .curved }
        m.drag(CGPoint(x: 0, y: 0), CGPoint(x: 200, y: 0))
        guard case .arrow(let g) = try #require(m.objects.first).shape else { Issue.record("not an arrow"); return }
        #expect(g.style == .curved)
        #expect(g.control != nil)
        #expect(HitTesting.handles(for: m.objects[0]).contains { $0.kind == .control })
    }

    @Test func penIsSmoothedIntoOneObjectAndShiftStraightens() throws {
        let m = makeModel(tool: .pen)
        m.drag(CGPoint(x: 0, y: 0), CGPoint(x: 300, y: 120), steps: 30)
        guard case .pen(let pts) = try #require(m.objects.first).shape else { Issue.record("not a pen stroke"); return }
        #expect(pts.count >= 2)
        m.drag(CGPoint(x: 0, y: 500), CGPoint(x: 300, y: 600), [.shift], steps: 30)
        guard case .pen(let straight) = m.objects[1].shape else { Issue.record("not a pen stroke"); return }
        #expect(straight.count == 2)
        // Two strokes, two undo steps.
        m.store.undo(); m.store.undo()
        #expect(m.objects.isEmpty)
    }

    @Test func highlighterModes() throws {
        let m = makeModel(tool: .highlighter)
        m.drag(CGPoint(x: 0, y: 50), CGPoint(x: 300, y: 50), steps: 10)
        guard case .highlight(.freehand) = try #require(m.objects.last).shape else { Issue.record("expected freehand"); return }
        m.library.update(.highlighter) { $0.highlightRect = true }
        m.drag(CGPoint(x: 0, y: 300), CGPoint(x: 300, y: 340))
        guard case .highlight(.rect(let r)) = try #require(m.objects.last).shape else { Issue.record("expected rect"); return }
        #expect(r == CGRect(x: 0, y: 300, width: 300, height: 40))
    }

    @Test func redactUsesToolMode() throws {
        let m = makeModel(tool: .redact)
        m.library.update(.redact) { $0.redactMode = .blur }
        m.drag(CGPoint(x: 10, y: 10), CGPoint(x: 110, y: 60))
        guard case .redact(_, let mode) = try #require(m.objects.first).shape else { Issue.record("not a redaction"); return }
        #expect(mode.kind == .blur)
    }

    @Test func styleScalesWithImageSize() {
        let small = makeModel(size: CGSize(width: 800, height: 500), tool: .arrow)
        let big = makeModel(size: CGSize(width: 5120, height: 2880), tool: .arrow)
        #expect(big.style(for: .arrow).lineWidth > small.style(for: .arrow).lineWidth * 3)
    }
}
