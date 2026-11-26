import AnnotationKit
import AppKit

/// Text, redaction and crop sections of the options bar.
extension OptionsBarView {
    func addTextOptions(_ s: ToolSettings) {
        addColors(s)
        add(controls.popup(["S", "M", "L", "XL", "XXL"], selected: s.sizeStep, label: String(localized: "Text size")) { [weak self] i in
            self?.change(String(localized: "Text Size")) { $0.sizeStep = i }
        })
        let decorations = TextStyle.Decoration.allCases
        add(controls.segmented(
            images: decorations.map(EditorIcons.textDecoration),
            labels: [String(localized: "Plain"), String(localized: "Outlined"), String(localized: "On solid pill"), String(localized: "On translucent pill")],
            selected: decorations.firstIndex(of: s.textStyle.decoration)
        ) { [weak self] i in
            self?.change(String(localized: "Text Style")) { $0.textStyle.decoration = decorations[i] }
        })
        add(controls.toggle(symbol: "bold", label: String(localized: "Bold"), on: s.textStyle.isBold) { [weak self] on in
            self?.change(String(localized: "Bold")) { $0.textStyle.isBold = on }
        })
        let alignments = TextStyle.Alignment.allCases
        add(controls.segmented(
            images: ["text.alignleft", "text.aligncenter", "text.alignright"].map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) ?? NSImage() },
            labels: [String(localized: "Align left"), String(localized: "Align centre"), String(localized: "Align right")],
            selected: alignments.firstIndex(of: s.textStyle.alignment)
        ) { [weak self] i in
            self?.change(String(localized: "Alignment")) { $0.textStyle.alignment = alignments[i] }
        })
        addOpacity(s)
    }

    func addRedactOptions(_ s: ToolSettings) {
        let kinds = RedactMode.Kind.allCases
        add(controls.segmented(
            images: ["square.grid.3x3.fill", "drop.fill", "rectangle.fill"].map { NSImage(systemSymbolName: $0, accessibilityDescription: nil) ?? NSImage() },
            labels: [String(localized: "Pixelate"), String(localized: "Blur"), String(localized: "Solid")],
            selected: kinds.firstIndex(of: s.redactMode.kind)
        ) { [weak self] i in
            self?.change(String(localized: "Redaction")) {
                let kind = kinds[i]
                $0.redactMode = RedactMode(kind: kind, strength: kind == .solid ? 1 : ($0.redactMode.kind == .solid ? 0.6 : $0.redactMode.strength))
            }
        })
        if s.redactMode.kind == .solid {
            addColors(s)
        } else {
            add(OptionControls.icon("dial.medium", label: String(localized: "Strength")))
            add(controls.slider(value: s.redactMode.strength, min: 0.2, max: 1, width: 90, label: String(localized: "Strength")) { [weak self] v, final in
                self?.change(String(localized: "Strength"), final: final) { $0.redactMode.strength = v }
            })
        }
    }

    func addCropControls() {
        let aspects = CropAspect.allCases
        add(OptionControls.caption(String(localized: "Aspect")))
        add(controls.popup(aspects.map(\.title), selected: aspects.firstIndex(of: model.cropAspect) ?? 0,
                                  label: String(localized: "Crop aspect")) { [weak self] i in
            self?.model.cropAspect = aspects[i]
            self?.onCropAspect?()
        })
        let draft = model.cropDraft ?? model.imageBounds
        let w = controls.numberField(Int(draft.width), label: String(localized: "Width in pixels")) { [weak self] v in
            self?.onCropSize?(CGFloat(v), nil)
        }
        let h = controls.numberField(Int(draft.height), label: String(localized: "Height in pixels")) { [weak self] v in
            self?.onCropSize?(nil, CGFloat(v))
        }
        setCropFields(w, h)
        add(w)
        add(OptionControls.caption("×"))
        add(h)
        add(OptionControls.caption(String(localized: "px")))
        add(OptionControls.separator())
        let cancel = controls.button(String(localized: "Cancel")) { [weak self] in self?.onCropCancel?() }
        let apply = controls.button(String(localized: "Apply Crop")) { [weak self] in self?.onCropApply?() }
        apply.keyEquivalent = ""
        apply.bezelColor = .controlAccentColor
        add(cancel)
        add(apply)
        add(OptionControls.caption(String(localized: "Return applies, Esc cancels")))
    }
}

extension OptionsBarView {
    func setCropFields(_ w: NSTextField, _ h: NSTextField) {
        widthField = w
        heightField = h
    }

    /// Keeps W×H in sync while the crop frame is dragged.
    func updateCropFields() {
        guard let draft = model.cropDraft else { return }
        if let w = widthField, w.currentEditor() == nil { w.stringValue = String(Int(draft.width)) }
        if let h = heightField, h.currentEditor() == nil { h.stringValue = String(Int(draft.height)) }
    }
}
