import AnnotationKit
import AppKit
import ShotzUI

/// Text, redaction and crop sections of the options bar.
extension OptionsBarView {
    func addTextOptions(_ s: ToolSettings) {
        addColors(s)
        // Text size: a pop-up of point sizes (six steps would take a quarter of the bar as segments).
        let sizes = controls.popup(ObjectStyle.textSizeSteps.map { "\(Int($0)) pt" }, selected: s.sizeStep,
                                   label: String(localized: "Text size")) { [weak self] i in
            self?.change(String(localized: "Text Size")) { $0.sizeStep = i }
        }
        add(sizes, String(localized: "Size"))
        let decorations = TextStyle.Decoration.allCases
        add(controls.segmented(
            glyphs: decorations.map { .textDecoration($0) },
            labels: [String(localized: "Plain"), String(localized: "Outlined"), String(localized: "On solid pill"), String(localized: "On translucent pill")],
            selected: decorations.firstIndex(of: s.textStyle.decoration), label: String(localized: "Text style")
        ) { [weak self] i in
            self?.change(String(localized: "Text Style")) { $0.textStyle.decoration = decorations[i] }
        }, String(localized: "Style"))
        add(controls.toggleChip(title: String(localized: "Bold"), glyph: .bold, tooltip: String(localized: "Bold"), on: s.textStyle.isBold) { [weak self] on in
            self?.change(String(localized: "Bold")) { $0.textStyle.isBold = on }
        }, String(localized: "Weight"), priority: .medium)
        let alignments = TextStyle.Alignment.allCases
        add(controls.segmented(
            glyphs: alignments.map { .textAlign($0) },
            labels: [String(localized: "Align left"), String(localized: "Align centre"), String(localized: "Align right")],
            selected: alignments.firstIndex(of: s.textStyle.alignment), label: String(localized: "Alignment")
        ) { [weak self] i in
            self?.change(String(localized: "Alignment")) { $0.textStyle.alignment = alignments[i] }
        }, String(localized: "Align"), priority: .low)
        addOpacity(s)
    }

    func addRedactOptions(_ s: ToolSettings) {
        let kinds = RedactMode.Kind.allCases
        add(controls.segmented(
            glyphs: kinds.map { .redactMode($0) },
            labels: [String(localized: "Pixelate"), String(localized: "Blur"), String(localized: "Solid")],
            selected: kinds.firstIndex(of: s.redactMode.kind), label: String(localized: "Redaction")
        ) { [weak self] i in
            self?.change(String(localized: "Redaction")) {
                let kind = kinds[i]
                $0.redactMode = RedactMode(kind: kind, strength: kind == .solid ? 1 : ($0.redactMode.kind == .solid ? 0.6 : $0.redactMode.strength))
            }
        }, String(localized: "Method"))
        if s.redactMode.kind == .solid {
            addColors(s)
        } else {
            add(controls.slider(value: s.redactMode.strength, min: 0.2, max: 1, width: 88, label: String(localized: "Strength"),
                                glyph: .strength, format: EditorControls.percent) { [weak self] v, final in
                self?.change(String(localized: "Strength"), final: final) { $0.redactMode.strength = v }
            }, String(localized: "Strength"))
        }
    }

    func addCropControls() {
        let aspects = CropAspect.allCases
        add(controls.popup(aspects.map(\.title), selected: aspects.firstIndex(of: model.cropAspect) ?? 0,
                           label: String(localized: "Crop aspect")) { [weak self] i in
            self?.model.cropAspect = aspects[i]
            self?.onCropAspect?()
        }, String(localized: "Aspect"))
        let draft = model.cropDraft ?? model.imageBounds
        let w = controls.numberField(Int(draft.width), label: String(localized: "Width in pixels")) { [weak self] v in
            self?.onCropSize?(CGFloat(v), nil)
        }
        let h = controls.numberField(Int(draft.height), label: String(localized: "Height in pixels")) { [weak self] v in
            self?.onCropSize?(nil, CGFloat(v))
        }
        widthField = w
        heightField = h
        add(Self.row([w, EditorControls.caption("×"), h]), String(localized: "Size"))
        let cancel = controls.secondaryButton(String(localized: "Cancel"), tooltip: String(localized: "Cancel"), shortcut: "Esc") { [weak self] in
            self?.onCropCancel?()
        }
        let apply = controls.primaryButton(String(localized: "Apply"), tooltip: String(localized: "Apply crop"), shortcut: "Return") { [weak self] in
            self?.onCropApply?()
        }
        let actions = ShotzToolbarStack(groups: [[cancel, apply]])
        actions.itemGap = ShotzUI.Space.s
        actions.showsSeparators = false
        add(actions, String(localized: "Crop"))
    }
}

extension OptionsBarView {
    /// Keeps W×H in sync while the crop frame is dragged (not while one is being typed in).
    func updateCropFields() {
        guard let draft = model.cropDraft else { return }
        for (field, v) in [(widthField, draft.width), (heightField, draft.height)] {
            guard let field, !Self.isEditing(field) else { continue }
            field.value = Double(Int(v))
        }
    }

    static func isEditing(_ field: ShotzNumberField) -> Bool {
        (field.window?.firstResponder as? NSView)?.isDescendant(of: field) == true
    }
}
