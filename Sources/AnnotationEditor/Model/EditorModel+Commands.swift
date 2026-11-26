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
            CounterNumberingShim.remove(ids, from: &doc)
        }
        clearSelection()
    }

    /// Arrow keys: 1 px, ⇧ 10 px. Repeated nudges are separate undo steps.
    func nudge(dx: CGFloat, dy: CGFloat) {
        let ids = selection
        guard !ids.isEmpty else { return }
        store.perform(String(localized: "Move")) { doc in
            for id in ids {
                guard let i = doc.index(of: id) else { continue }
                doc.objects[i].shape = doc.objects[i].shape.offset(by: CGVector(dx: dx, dy: dy))
            }
        }
    }

    /// ⌘D: duplicates the selection, offset so the copy is visible.
    func duplicateSelection() {
        let objects = selectedObjects
        guard !objects.isEmpty else { return }
        insert(objects, offset: CGVector(dx: unit * 4, dy: unit * 4), actionName: String(localized: "Duplicate"))
    }

    /// Inserts copies (fresh ids) on top and selects them.
    func insert(_ objects: [AnnotationObject], offset: CGVector, actionName: String) {
        var copies: [AnnotationObject] = []
        store.perform(actionName) { doc in
            for object in objects {
                var copy = object.duplicated(offsetBy: offset)
                if case .counter(var c) = copy.shape {
                    c.value = CounterNumberingShim.nextValue(in: doc, numbering: c.numbering, start: c.value)
                    copy.shape = .counter(c)
                }
                doc.objects.append(copy)
                copies.append(copy)
            }
        }
        select(copies.map(\.id))
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
            doc.objects = Self.arranged(doc.objects, ids: ids, arrangement)
        }
    }

    static func arranged(
        _ objects: [AnnotationObject], ids: Set<AnnotationObject.ID>, _ arrangement: Arrangement
    ) -> [AnnotationObject] {
        var objs = objects
        switch arrangement {
        case .front:
            return objs.filter { !ids.contains($0.id) } + objs.filter { ids.contains($0.id) }
        case .back:
            return objs.filter { ids.contains($0.id) } + objs.filter { !ids.contains($0.id) }
        case .forward:
            var i = objs.count - 2
            while i >= 0 {
                if ids.contains(objs[i].id), !ids.contains(objs[i + 1].id) { objs.swapAt(i, i + 1) }
                i -= 1
            }
            return objs
        case .backward:
            for i in 1..<max(objs.count, 1) where ids.contains(objs[i].id) && !ids.contains(objs[i - 1].id) {
                objs.swapAt(i, i - 1)
            }
            return objs
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
            return ToolSettings.from(first, unit: unit, base: settings(for: kind))
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
        let unit = self.unit
        let library = self.library
        let apply: (inout AnnotationDocument) -> Void = { doc in
            for object in objects {
                guard let i = doc.index(of: object.id) else { continue }
                let kind = ToolKind.forShape(object.shape)
                var s = ToolSettings.from(doc.objects[i], unit: unit, base: library.settings(for: kind))
                change(&s)
                doc.objects[i] = Self.restyled(doc.objects[i], with: s, kind: kind, unit: unit)
            }
        }
        if store.isInteractive { store.updateInteractive(apply) } else { store.perform(name, apply) }
        for kind in Set(objects.map { ToolKind.forShape($0.shape) }) { library.update(kind, change) }
        notify(.toolSettings)
    }

    /// Applies settings to an existing object, keeping its geometry.
    static func restyled(_ object: AnnotationObject, with s: ToolSettings, kind: ToolKind, unit: CGFloat) -> AnnotationObject {
        var o = object
        o.style = s.objectStyle(for: kind, unit: unit)
        // Keep a font size that was scaled freely with the corner handles
        // unless the size step itself changed.
        let oldStep = ToolSettings.from(object, unit: unit, base: s).sizeStep
        if oldStep == s.sizeStep { o.style.fontSize = object.style.fontSize }
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

    // MARK: Counter value

    /// Types over the value of a selected counter.
    func setCounterValue(_ value: Int, for id: AnnotationObject.ID) {
        guard let object = document[id: id], case .counter(var c) = object.shape else { return }
        c.value = max(1, value)
        store.perform(String(localized: "Change Number")) { doc in
            doc[id: id]?.shape = .counter(c)
        }
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
