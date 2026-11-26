import AnnotationKit
import Foundation

/// Single-key shortcuts while no text is being edited (SPEC §5.3), arrow-key
/// nudges, Delete, and the Esc/Return rules (SPEC §5.1). UI-free; unit-tested.
@MainActor final class EditorKeyHandler {
    enum Key: Equatable {
        case character(Character)
        case escape, returnKey, delete
        case arrow(dx: CGFloat, dy: CGFloat)
    }

    private let model: EditorModel
    var onToggleBackground: (() -> Void)?
    /// Typed digits over a selected counter accumulate briefly ("1", "2" → 12).
    private var counterDigits = ""
    private var lastDigitTime = Date.distantPast
    var now: () -> Date = Date.init

    init(model: EditorModel) {
        self.model = model
    }

    /// Returns true when handled. `shift` applies to arrows (10 px).
    func handle(_ key: Key, shift: Bool = false) -> Bool {
        switch key {
        case .escape:
            if model.tool.keyDown(.escape) { return true }
            if !model.selection.isEmpty { model.clearSelection(); return true }
            if model.toolKind != .select { model.setTool(.select); return true }
            return true // Esc never closes the window.
        case .returnKey:
            if model.tool.keyDown(.returnKey) { return true }
            if model.selection.count == 1, let object = model.selectedObjects.first, case .text = object.shape {
                model.textHost?.beginEditing(object, isNew: false)
                return true
            }
            return false
        case .delete:
            guard !model.selection.isEmpty else { return false }
            model.deleteSelection()
            return true
        case .arrow(let dx, let dy):
            guard !model.selection.isEmpty else { return false }
            let step: CGFloat = shift ? 10 : 1
            model.nudge(dx: dx * step, dy: dy * step)
            return true
        case .character(let c):
            return character(Character(c.lowercased()))
        }
    }

    private func character(_ c: Character) -> Bool {
        if model.tool.keyDown(.character(c)) { return true }
        if let digit = c.wholeNumberValue {
            if typeCounterDigit(digit) { return true }
            guard (1...8).contains(digit) else { return false }
            model.changeOption(String(localized: "Colour")) { $0.color = RGBAColor.presets[digit - 1] }
            return true
        }
        counterDigits = ""
        if c == "g" {
            onToggleBackground?()
            return true
        }
        guard let kind = ToolKind.forKey(c) else { return false }
        if kind == .arrow, model.toolKind == .arrow {
            // A again cycles the arrow style (and restyles selected arrows).
            let next = model.displayedSettings.arrowStyle.next
            model.changeOption(String(localized: "Arrow Style")) { $0.arrowStyle = next }
            return true
        }
        model.setTool(kind)
        return true
    }

    /// A selected counter's value can be typed over.
    private func typeCounterDigit(_ digit: Int) -> Bool {
        guard model.selection.count == 1, let object = model.selectedObjects.first, case .counter = object.shape else {
            counterDigits = ""
            return false
        }
        let t = now()
        if t.timeIntervalSince(lastDigitTime) > 1 { counterDigits = "" }
        lastDigitTime = t
        counterDigits.append(String(digit))
        if counterDigits.count > 3 { counterDigits = String(digit) }
        guard let value = Int(counterDigits), value > 0 else { return true }
        model.setCounterValue(value, for: object.id)
        return true
    }
}
