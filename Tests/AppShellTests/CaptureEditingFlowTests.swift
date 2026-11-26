import Foundation
import Testing
@testable import AppShell
import ShotzCore

@MainActor final class FakeStack: QuickAccessPresenting {
    weak var delegate: QuickAccessDelegate?
    enum Event: Equatable { case present(UUID, URL?, UInt32), dismiss(UUID), dismissAll }
    private(set) var events: [Event] = []
    private(set) var cards: [UUID: CaptureResult] = [:]

    func present(_ capture: CaptureResult, imageURL: URL?) {
        events.append(.present(capture.id, imageURL, capture.displayID))
        cards[capture.id] = capture
    }
    func dismiss(id: CaptureResult.ID) {
        events.append(.dismiss(id))
        cards[id] = nil
    }
    func dismissAll() {
        events.append(.dismissAll)
        cards.removeAll()
    }
}

@MainActor final class FakeEditor: AnnotationEditing {
    weak var delegate: AnnotationEditingDelegate?
    private(set) var opened: [CaptureResult] = []
    func openEditor(for capture: CaptureResult) { opened.append(capture) }
    func openEditor(imageAt url: URL) {}
    /// Simulates the user closing the window.
    func close(_ capture: CaptureResult, rendered: URL?, display: UInt32?) {
        delegate?.editor(didClose: capture, renderedImageURL: rendered, onDisplay: display)
    }
}

@MainActor
struct CaptureEditingFlowTests {
    let capture = CaptureResult(fileURL: URL(filePath: "/tmp/c/Shotz A.png"), displayName: "Shotz A", kind: .area,
                                pixelSize: CGSize(width: 400, height: 300), scale: 2, displayID: 1)
    let rendered = URL(filePath: "/tmp/c/Documents/a.png")

    func make(renders: [UUID: URL] = [:]) -> (CaptureEditingFlow, FakeStack, FakeEditor) {
        let stack = FakeStack(), editor = FakeEditor()
        let flow = CaptureEditingFlow(quickAccess: stack, editor: editor) { renders[$0] }
        editor.delegate = flow
        return (flow, stack, editor)
    }

    @Test func protocolConveniencePresentsTheCapturesOwnImage() {
        let stack = FakeStack()
        let presenting: QuickAccessPresenting = stack
        presenting.present(capture)
        #expect(stack.events == [.present(capture.id, nil, 1)])
    }

    @Test func annotateThenCloseReturnsTheAnnotatedCardOnTheEditorsDisplay() {
        let (flow, stack, editor) = make()
        var presented: [UUID] = []
        flow.didPresent = { presented.append($0.id) }
        flow.presentInStack(capture)
        flow.openInEditor(capture)                       // card's Annotate
        #expect(stack.cards[capture.id] == nil)         // one capture, one place
        #expect(editor.opened.map(\.id) == [capture.id])

        editor.close(capture, rendered: rendered, display: 7)
        #expect(stack.events.last == .present(capture.id, rendered, 7))
        #expect(stack.cards[capture.id]?.id == capture.id)
        #expect(stack.cards[capture.id]?.displayID == 7)
        #expect(stack.cards[capture.id]?.fileURL == capture.fileURL)   // same capture, same document
        #expect(presented == [capture.id, capture.id])

        // Annotate on the returned card reopens the same capture (same document).
        flow.openInEditor(capture)
        #expect(editor.opened.map(\.id) == [capture.id, capture.id])
    }

    @Test func closeWithoutEditsReturnsTheOriginalImageWhereItWas() {
        let (flow, stack, editor) = make()   // the editor's delegate is weak: keep the flow alive
        editor.close(capture, rendered: nil, display: nil)
        #expect(stack.events == [.present(capture.id, nil, 1)])
        withExtendedLifetime(flow) {}
    }

    @Test func openingFromHistoryOrMenuHidesAnExistingCardAndReturnsItOnClose() {
        let (flow, stack, editor) = make()
        flow.presentInStack(capture)
        flow.openInEditor(capture)                       // "Open Last Capture in Editor"
        #expect(stack.events == [.present(capture.id, nil, 1), .dismiss(capture.id)])
        editor.close(capture, rendered: rendered, display: 2)
        #expect(stack.events.last == .present(capture.id, rendered, 2))
    }

    @Test func stackPresentsShowTheRenderWhenOneExists() {
        let (flow, stack, _) = make(renders: [capture.id: rendered])
        flow.presentInStack(capture)                     // history click or restore
        #expect(stack.events == [.present(capture.id, rendered, 1)])
    }

    @Test func attachMakesTheFlowTheEditorsDelegate() {
        let stack = FakeStack(), editor = FakeEditor()
        let flow = CaptureEditingFlow(quickAccess: stack, editor: editor) { _ in nil }
        #expect(editor.delegate == nil)
        flow.attach(to: editor)
        #expect(editor.delegate === flow)
    }

    @Test func historyHooksPointAtTheStore() async throws {
        let paths = ShotzPaths(root: FileManager.default.temporaryDirectory.appending(path: "ShotzHooks-\(UUID().uuidString)", directoryHint: .isDirectory))
        defer { try? FileManager.default.removeItem(at: paths.root) }
        let history = FileHistoryStore(paths: paths)
        let hooks = HistoryEditorHooks(history: history)
        let id = UUID()
        #expect(hooks.documentURL(id) == history.documentURL(for: id))
        #expect(hooks.renderedURL(id) == history.renderedURL(for: id))
        #expect(hooks.renderedURL(id).lastPathComponent == "\(id.uuidString).png")
        #expect(await hooks.previousExport(id) == nil)
    }

    @Test func onDisplayKeepsIdentity() {
        let moved = capture.onDisplay(9)
        #expect(moved.id == capture.id && moved.fileURL == capture.fileURL && moved.createdAt == capture.createdAt)
        #expect(moved.displayID == 9)
    }
}
