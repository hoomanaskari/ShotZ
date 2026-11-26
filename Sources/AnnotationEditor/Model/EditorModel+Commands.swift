import AnnotationKit
import CoreGraphics
import Foundation

/// Edit, arrange and style commands. Each is one undo step.
extension EditorModel {
    func selectAll() {
        select(document.objects.map(\.id))
    }

    func deleteSelection() {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        store.perform(String(localized: "Delete")) { doc in
            doc.removeObjects(ids)
        }
        clearSelection()
    }

    /// Arrow keys: 1 px, ⇧ 10 px. Repeated nudges are separate undo steps.
    func nudge(dx: CGFloat, dy: CGFloat) {
        let ids = selection
        guard !ids.isEmpty else { return }
        store.perform(String(localized: "Move")) { doc in
            for id in ids {
                guard let object = doc[id: id] else { continue }
                doc[id: id] = ObjectGeometry.moved(object, by: CGVector(dx: dx, dy: dy))
            }
        }
    }

    /// ⌘D: duplicates the selection, offset so the copy is visible.
    func duplicateSelection() {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        var copies: [AnnotationObject.ID] = []
        store.perform(String(localized: "Duplicate")) { doc in
            copies = doc.duplicate(ids, offset: doc.defaultPasteOffset)
        }
        select(copies)
    }

    /// Inserts copies (fresh ids) on top and selects them.
    func insert(_ objects: [AnnotationObject], offset: CGVector, actionName: String) {
        var copies: [AnnotationObject.ID] = []
        store.perform(actionName) { doc in
            copies = doc.paste(objects, offset: offset)
        }
        select(copies)
    }

    // MARK: Z-order

    enum Arrangement { case forward, backward, front, back }

    func arrange(_ arrangement: Arrangement) {
        let ids = Set(selection)
        guard !ids.isEmpty else { return }
        let name: String = switch arrangement {
        case .forward: String(localized: "Bring Forward")
        case .backward: String(localized: "Send Backward")
        case .front: String(localized: "Bring to Front")
        case .back: String(localized: "Send to Back")
        }
        store.perform(name) { doc in
            switch arrangement {
            case .forward: doc.bringForward(ids)
            case .backward: doc.sendBackward(ids)
            case .front: doc.bringToFront(ids)
            case .back: doc.sendToBack(ids)
            }
        }
    }

    // MARK: Options

    /// The tool whose options the options bar shows: the selection's kind
    /// (when homogeneous) under Select, otherwise the active tool.
    var optionsKind: ToolKind? {
        let kinds = Set(selectedObjects.map { ToolKind.forShape($0.shape) })
        if kinds.count == 1, let k = kinds.first { return k }
        if !kinds.isEmpty { return nil } // mixed selection: common options only
        return toolKind
    }

    /// Settings displayed in the options bar.
    var displayedSettings: ToolSettings {
        if let first = selectedObjects.first {
            let kind = ToolKind.forShape(first.shape)
            return ToolSettings.from(first, pixelSize: document.pixelSize, scale: document.scale, base: settings(for: kind))
        }
        return settings(for: toolKind)
    }

    /// Changing an option: restyles the selection, otherwise sets the default
    /// for the next object. Either way it is remembered as the last-used style.
    func changeOption(_ name: String, _ change: @escaping (inout ToolSettings) -> Void) {
        let objects = selectedObjects
        if objects.isEmpty {
            library.update(toolKind, change)
            notify(.toolSettings)
            return
        }
        let library = self.library
        let apply: (inout AnnotationDocument) -> Void = { doc in
            for object in objects {
                guard let i = doc.index(of: object.id) else { continue }
                let kind = ToolKind.forShape(object.shape)
                var s = ToolSettings.from(doc.objects[i], pixelSize: doc.pixelSize, scale: doc.scale, base: library.settings(for: kind))
                let before = s
                change(&s)
                doc.objects[i] = Self.restyled(doc.objects[i], from: before, to: s, kind: kind, document: doc)
            }
        }
        if store.isInteractive { store.updateInteractive(apply) } else { store.perform(name, apply) }
        for kind in Set(objects.map { ToolKind.forShape($0.shape) }) { library.update(kind, change) }
        notify(.toolSettings)
    }

    /// Applies changed settings to an existing object, keeping its geometry, and
    /// keeping sizes that were set freely (handles) unless their step changed.
    static func restyled(
        _ object: AnnotationObject, from before: ToolSettings, to s: ToolSettings, kind: ToolKind, document: AnnotationDocument
    ) -> AnnotationObject {
        var o = object
        let fresh = s.objectStyle(for: kind, pixelSize: document.pixelSize, scale: document.scale)
        o.style.color = fresh.color
        o.style.opacity = fresh.opacity
        o.style.fill = fresh.fill
        o.style.dash = fresh.dash
        o.style.contrastOutline = fresh.contrastOutline
        if s.thicknessStep != before.thicknessStep { o.style.lineWidth = fresh.lineWidth }
        if s.sizeStep != before.sizeStep { o.style.fontSize = fresh.fontSize }
        let unit = ObjectStyle.thicknessUnit(for: document.pixelSize)
        switch o.shape {
        case .arrow(var g):
            if g.style != s.arrowStyle {
                g.style = s.arrowStyle
                if g.style == .curved, g.control == nil { g.control = ArrowCurve.defaultControl(start: g.start, end: g.end) }
            }
            o.shape = .arrow(g)
        case .rectangle(let r, _):
            o.shape = .rectangle(r, cornerRadius: s.cornerRadiusUnits * unit)
        case .text(var box):
            box.style = s.textStyle
            o.shape = .text(box)
        case .redact(let r, _):
            o.shape = .redact(r, s.redactMode)
        case .counter(var c):
            c.numbering = s.counterNumbering
            o.shape = .counter(c)
        default:
            break
        }
        return o
    }

    // MARK: Background

    func setBackground(_ background: BackgroundStyle?, interactive: Bool) {
        let name = String(localized: "Background")
        if interactive {
            if !store.isInteractive { store.beginInteractiveChange(name) }
            store.updateInteractive { $0.background = background }
        } else {
            if store.isInteractive { store.commitInteractiveChange() }
            store.perform(name) { $0.background = background }
        }
    }
}

/// Default curve for a new curved arrow: a gentle bow to the left of travel.
enum ArrowCurve {
    static func defaultControl(start: CGPoint, end: CGPoint) -> CGPoint {
        let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2)
        let dx = end.x - start.x, dy = end.y - start.y
        return CGPoint(x: mid.x + dy * 0.2, y: mid.y - dx * 0.2)
    }
}
