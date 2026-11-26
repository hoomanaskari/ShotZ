import AnnotationKit
import Foundation

/// Typing over a counter's value (SPEC 5.3). Return or a double-click enters value
/// editing; digits then replace the number, Delete removes the last digit, Return
/// (or clicking elsewhere) commits, Esc cancels. One undo step per edit. Outside
/// this mode digits pick colours 1–8 as usual.
extension EditorModel {
    func beginCounterValueEditing(_ id: AnnotationObject.ID) {
        guard let object = document[id: id], case .counter = object.shape else { return }
        if editingCounterID != nil { endCounterValueEditing(commit: true) }
        select([id])
        counterDigits = ""
        store.beginInteractiveChange(String(localized: "Change Number"))
        editingCounterID = id
    }

    func typeCounterDigit(_ digit: Int) {
        guard editingCounterID != nil else { return }
        counterDigits.append(String(digit))
        if counterDigits.count > 3 { counterDigits = String(counterDigits.suffix(3)) }
        applyCounterDigits()
    }

    func deleteCounterDigit() {
        guard editingCounterID != nil, !counterDigits.isEmpty else { return }
        counterDigits.removeLast()
        applyCounterDigits()
    }

    private func applyCounterDigits() {
        guard let id = editingCounterID, let value = Int(counterDigits), value > 0 else { return }
        store.updateInteractive { doc in
            guard case .counter(var c) = doc[id: id]?.shape else { return }
            c.value = value
            doc[id: id]?.shape = .counter(c)
        }
    }

    func endCounterValueEditing(commit: Bool) {
        guard editingCounterID != nil else { return }
        editingCounterID = nil
        counterDigits = ""
        if store.isInteractive {
            if commit { store.commitInteractiveChange() } else { store.cancelInteractiveChange() }
        }
    }

    /// Double-click or Return on an object: edit a text in place, or a counter's value.
    @discardableResult
    func beginEditing(_ id: AnnotationObject.ID) -> Bool {
        guard let object = document[id: id] else { return false }
        switch object.shape {
        case .text:
            select([id])
            textHost?.beginEditing(object, isNew: false)
            return true
        case .counter:
            beginCounterValueEditing(id)
            return true
        default:
            return false
        }
    }
}
