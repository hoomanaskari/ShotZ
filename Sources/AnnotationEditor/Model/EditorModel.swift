import AnnotationKit
import CoreGraphics
import Foundation

/// Hosts in-place text editing (the canvas). Absent in unit tests.
@MainActor protocol TextEditingHost: AnyObject {
    func beginEditing(_ object: AnnotationObject, isNew: Bool)
    /// Commits (or discards) the running edit, if any.
    func endEditing()
    var isEditingText: Bool { get }
}

/// Per-window editor state: the document store, selection, tools and the
/// transient overlay state (guides, marquee, crop draft). UI-free and unit-tested.
@MainActor final class EditorModel {
    enum Event { case selection, tool, overlay, toolSettings }

    let store: DocumentStore
    let library: ToolSettingsLibrary
    /// Reads the "Snap while moving and cropping" setting.
    var snappingSetting: () -> Bool = { true }
    /// Reads the "Return to Select after drawing" setting.
    var returnToSelectSetting: () -> Bool = { false }
    weak var textHost: TextEditingHost?

    private(set) var selection: [AnnotationObject.ID] = []
    private(set) var toolKind: ToolKind = .select
    private(set) var tool: Tool
    /// Screen points per image pixel (scroll view magnification); for tolerances.
    var pointsPerPixel: CGFloat = 1

    // Overlay state drawn by the canvas.
    var guides: [SnapGuide] = [] { didSet { if guides != oldValue { notify(.overlay) } } }
    var marquee: CGRect? { didSet { if marquee != oldValue { notify(.overlay) } } }
    var cropDraft: CGRect? { didSet { if cropDraft != oldValue { notify(.overlay) } } }
    var cropAspect: CropAspect = .free { didSet { notify(.toolSettings) } }
    /// Objects hidden while they are edited in place.
    var hiddenObjectIDs: Set<AnnotationObject.ID> = [] { didSet { if hiddenObjectIDs != oldValue { notify(.overlay) } } }

    private var observers: [(Event) -> Void] = []

    init(store: DocumentStore, library: ToolSettingsLibrary, initialTool: ToolKind = .select) {
        self.store = store
        self.library = library
        tool = SelectTool()
        setTool(initialTool)
    }

    func observe(_ handler: @escaping (Event) -> Void) { observers.append(handler) }
    func notify(_ event: Event) { for o in observers { o(event) } }

    var document: AnnotationDocument { store.document }
    var unit: CGFloat { ObjectStyle.thicknessUnit(for: document.pixelSize) }
    var imageBounds: CGRect { CGRect(origin: .zero, size: document.pixelSize) }
    /// Hit tolerance: 5 screen points, in pixels.
    var tolerance: CGFloat { 5 / max(pointsPerPixel, 0.0001) }
    /// Drag threshold: 3 screen points, in pixels.
    var dragThreshold: CGFloat { 3 / max(pointsPerPixel, 0.0001) }

    // MARK: Tools

    func setTool(_ kind: ToolKind) {
        if textHost?.isEditingText == true { textHost?.endEditing() }
        tool.deactivate()
        toolKind = kind
        tool = Self.makeTool(kind, model: self)
        guides = []
        marquee = nil
        tool.activate()
        if kind != .select && kind != .crop { library.lastTool = kind }
        notify(.tool)
    }

    private static func makeTool(_ kind: ToolKind, model: EditorModel) -> Tool {
        let tool: Tool
        switch kind {
        case .select: tool = SelectTool()
        case .arrow, .rectangle, .ellipse, .line, .redact: tool = ShapeTool(kind: kind)
        case .highlighter: tool = HighlighterTool()
        case .pen: tool = FreehandTool(kind: .pen)
        case .text: tool = TextTool()
        case .counter: tool = CounterTool()
        case .crop: tool = CropTool()
        }
        (tool as? ModelBound)?.model = model
        return tool
    }

    /// After an object was drawn: stay armed, or return to Select (setting).
    func didFinishDrawing() {
        if returnToSelectSetting() { setTool(.select) }
    }

    func settings(for kind: ToolKind) -> ToolSettings { library.settings(for: kind) }

    func style(for kind: ToolKind) -> ObjectStyle {
        settings(for: kind).objectStyle(for: kind, unit: unit)
    }

    // MARK: Selection

    func select(_ ids: [AnnotationObject.ID]) {
        let valid = ids.filter { document.index(of: $0) != nil }
        var unique: [AnnotationObject.ID] = []
        for id in valid where !unique.contains(id) { unique.append(id) }
        guard unique != selection else { return }
        selection = unique
        notify(.selection)
    }

    func toggleSelection(_ id: AnnotationObject.ID) {
        if selection.contains(id) { select(selection.filter { $0 != id }) } else { select(selection + [id]) }
    }

    func clearSelection() { select([]) }

    var selectedObjects: [AnnotationObject] { selection.compactMap { document[id: $0] } }

    /// Drops ids that no longer exist (after undo/redo).
    func pruneSelection() {
        let valid = selection.filter { document.index(of: $0) != nil }
        if valid != selection { selection = valid; notify(.selection) }
    }

    // MARK: Hit testing

    func hitObject(at point: CGPoint) -> AnnotationObject.ID? {
        var doc = document
        doc.objects.removeAll { hiddenObjectIDs.contains($0.id) }
        // Redactions render beneath everything: test the others first.
        let ordered = doc.objects.filter(\.isRedaction) + doc.objects.filter { !$0.isRedaction }
        doc.objects = ordered
        return HitTesting.object(at: point, in: doc, tolerance: tolerance)
    }

    /// A handle of a selected object under `point`.
    func hitHandle(at point: CGPoint) -> (AnnotationObject.ID, Handle)? {
        let radius = 7 / max(pointsPerPixel, 0.0001)
        for object in selectedObjects.reversed() {
            for handle in handles(for: object) where hypot(handle.position.x - point.x, handle.position.y - point.y) <= radius {
                return (object.id, handle)
            }
        }
        return nil
    }

    /// Handles shown for an object. With several objects selected only move is offered.
    func handles(for object: AnnotationObject) -> [Handle] {
        guard selection.count == 1 else { return [] }
        return HitTesting.handles(for: object)
    }

    // MARK: Snapping

    var isSnappingEnabled: Bool { snappingSetting() }

    /// Snap candidates: the visible image rect and every object not being moved.
    func snapCandidates(excluding ids: Set<AnnotationObject.ID>) -> [CGRect] {
        [document.imageRect] + document.objects.filter { !ids.contains($0.id) }.map { snapBounds(of: $0) }
    }

    /// Visual bounds used for snapping (without stroke padding for box shapes).
    func snapBounds(of object: AnnotationObject) -> CGRect {
        switch object.shape {
        case .rectangle(let r, _), .ellipse(let r), .redact(let r, _), .highlight(.rect(let r)):
            return r.standardized
        default:
            return AnnotationRenderer.bounds(of: object)
        }
    }

    /// Snap correction for a moving rect, updating the guides. ⌘ disables snapping.
    func snapOffset(for rect: CGRect, excluding ids: Set<AnnotationObject.ID>, modifiers: ToolModifiers) -> CGVector {
        guard isSnappingEnabled, !modifiers.contains(.command) else { guides = []; return .zero }
        let result = SnappingShim.snap(moving: rect, candidates: snapCandidates(excluding: ids), tolerance: tolerance)
        guides = result.guides
        return result.offset
    }

    func snapPoint(_ point: CGPoint, excluding ids: Set<AnnotationObject.ID>, modifiers: ToolModifiers) -> CGPoint {
        guard isSnappingEnabled, !modifiers.contains(.command) else { guides = []; return point }
        let (p, g) = SnappingShim.snap(point: point, candidates: snapCandidates(excluding: ids), tolerance: tolerance)
        guides = g
        return p
    }
}

/// Tools that hold a back reference to their model.
@MainActor protocol ModelBound: AnyObject {
    var model: EditorModel? { get set }
}
