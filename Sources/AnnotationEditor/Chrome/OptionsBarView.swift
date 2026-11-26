import AnnotationKit
import AppKit

/// Context options under the tool strip. Shows the options of the selection
/// (restyling it) or of the active tool (setting its defaults).
@MainActor final class OptionsBarView: NSView {
    let model: EditorModel
    private let stack = NSStackView()
    let controls = OptionControls()
    private var rebuildScheduled = false
    /// The crop tool's numeric fields and Apply/Cancel actions.
    var onCropApply: (() -> Void)?
    var onCropCancel: (() -> Void)?
    var onCropAspect: (() -> Void)?
    var onCropSize: ((CGFloat?, CGFloat?) -> Void)?
    /// Right-aligned accessory (zoom menu).
    var trailingView: NSView? { didSet { rebuild() } }

    static let colorNames = [
        String(localized: "Red"), String(localized: "Orange"), String(localized: "Yellow"), String(localized: "Green"),
        String(localized: "Blue"), String(localized: "Purple"), String(localized: "Black"), String(localized: "White"),
    ]

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .centerY
        stack.edgeInsets = NSEdgeInsets(top: 0, left: 12, bottom: 0, right: 12)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "Options"))
        model.observe { [weak self] event in
            switch event {
            case .tool, .selection: self?.scheduleRebuild()
            case .overlay where self?.model.toolKind == .crop: self?.updateCropFields()
            default: break
            }
        }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuild()
        }
    }

    // MARK: Build

    var widthField: NSTextField?
    var heightField: NSTextField?

    func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        controls.reset()
        widthField = nil
        heightField = nil
        let s = model.displayedSettings
        let hasSelection = !model.selection.isEmpty

        if model.toolKind == .crop {
            addCropControls()
        } else if let kind = hasSelection ? model.optionsKind : model.toolKind {
            if kind == .select {
                stack.addArrangedSubview(OptionControls.caption(String(localized: "Click to select, drag to select several, ⌘A selects all. Press a tool key to draw.")))
            } else {
                addOptions(for: kind, s)
            }
        } else {
            // Mixed selection: the options every object shares.
            addColors(s)
            add(thickness(s))
            addOpacity(s)
        }
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        stack.addArrangedSubview(spacer)
        if let trailingView { stack.addArrangedSubview(trailingView) }
    }

    func add(_ v: NSView) { stack.addArrangedSubview(v) }

    private func addOptions(for kind: ToolKind, _ s: ToolSettings) {
        switch kind {
        case .arrow:
            addColors(s)
            add(thickness(s))
            add(controls.segmented(images: ArrowStyle.allCases.map(EditorIcons.arrow), labels: ArrowStyle.allCases.map(Self.title),
                                   selected: ArrowStyle.allCases.firstIndex(of: s.arrowStyle)) { [weak self] i in
                self?.change(String(localized: "Arrow Style")) { $0.arrowStyle = ArrowStyle.allCases[i] }
            })
            add(controls.checkbox(String(localized: "Outline"), on: s.contrastOutline) { [weak self] on in
                self?.change(String(localized: "Outline")) { $0.contrastOutline = on }
            })
            addOpacity(s)
        case .rectangle:
            addColors(s)
            add(thickness(s))
            add(fillControl(s, modes: [.outline, .filled, .outlineTranslucentFill], ellipse: false))
            add(OptionControls.icon("square.dashed", label: String(localized: "Corner radius")))
            add(controls.slider(value: s.cornerRadiusUnits, min: 0, max: 12, width: 70, label: String(localized: "Corner radius")) { [weak self] v, final in
                self?.change(String(localized: "Corner Radius"), final: final) { $0.cornerRadiusUnits = v }
            })
            addOpacity(s)
        case .ellipse:
            addColors(s)
            add(thickness(s))
            add(fillControl(s, modes: [.outline, .filled], ellipse: true))
            addOpacity(s)
        case .line:
            addColors(s)
            add(thickness(s))
            let dashes = ObjectStyle.Dash.allCases
            add(controls.segmented(images: dashes.map(EditorIcons.dash), labels: [String(localized: "Solid"), String(localized: "Dashed")],
                                   selected: dashes.firstIndex(of: s.dash)) { [weak self] i in
                self?.change(String(localized: "Line Style")) { $0.dash = dashes[i] }
            })
            addOpacity(s)
        case .text:
            addTextOptions(s)
        case .highlighter:
            addColors(s)
            add(controls.segmented(
                images: [symbol("highlighter"), symbol("rectangle.fill")],
                labels: [String(localized: "Freehand marker"), String(localized: "Rectangle highlight")],
                selected: s.highlightRect ? 1 : 0
            ) { [weak self] i in
                self?.change(String(localized: "Highlighter")) { $0.highlightRect = i == 1 }
            })
            add(thickness(s))
            addOpacity(s)
        case .redact:
            addRedactOptions(s)
        case .counter:
            addColors(s)
            add(controls.segmented(titles: ["S", "M", "L", "XL"], selected: s.sizeStep) { [weak self] i in
                self?.change(String(localized: "Counter Size")) { $0.sizeStep = i }
            })
            add(controls.segmented(titles: ["1 2 3", "A B C"], selected: s.counterNumbering == .numeric ? 0 : 1) { [weak self] i in
                self?.change(String(localized: "Numbering")) { $0.counterNumbering = i == 0 ? .numeric : .alphabetic }
            })
            add(OptionControls.caption(String(localized: "Start at")))
            add(controls.numberField(s.counterStart, width: 40, label: String(localized: "Start value")) { [weak self] v in
                self?.model.library.update(.counter) { $0.counterStart = max(1, v) }
            })
        case .pen:
            addColors(s)
            add(thickness(s))
            addOpacity(s)
        case .select, .crop:
            break
        }
    }

    // MARK: Pieces

    private func symbol(_ name: String) -> NSImage {
        NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
    }

    func change(_ name: String, final: Bool = true, _ apply: @escaping (inout ToolSettings) -> Void) {
        if !final, !model.selection.isEmpty, !model.store.isInteractive {
            model.store.beginInteractiveChange(name)
        }
        model.changeOption(name, apply)
        if final {
            if model.store.isInteractive { model.store.commitInteractiveChange() }
            scheduleRebuild()
        }
    }

    func addColors(_ s: ToolSettings) {
        for (i, preset) in RGBAColor.presets.enumerated() {
            let color = NSColor(cgColor: preset.cgColor) ?? .red
            let b = controls.imageButton(EditorIcons.swatch(color, selected: preset == s.color), label: Self.colorNames[i]) { [weak self] in
                self?.change(String(localized: "Colour")) { $0.color = preset }
            }
            b.toolTip = "\(Self.colorNames[i]) (\(i + 1))"
            add(b)
        }
        let current = NSColor(cgColor: s.color.cgColor) ?? .red
        add(controls.colorWell(current, label: String(localized: "Custom colour")) { [weak self] color, final in
            guard let srgb = color.usingColorSpace(.sRGB) else { return }
            let c = RGBAColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
            self?.change(String(localized: "Colour"), final: final) { $0.color = c }
        })
        add(OptionControls.separator())
    }

    private func thickness(_ s: ToolSettings) -> NSView {
        controls.segmented(
            images: (0..<5).map(EditorIcons.thickness),
            labels: [String(localized: "Extra thin"), String(localized: "Thin"), String(localized: "Medium"),
                     String(localized: "Thick"), String(localized: "Extra thick")],
            selected: s.thicknessStep
        ) { [weak self] i in
            self?.change(String(localized: "Thickness")) { $0.thicknessStep = i }
        }
    }

    func addOpacity(_ s: ToolSettings) {
        add(OptionControls.icon("circle.lefthalf.filled", label: String(localized: "Opacity")))
        add(controls.slider(value: s.opacity, min: 0.1, max: 1, width: 70, label: String(localized: "Opacity")) { [weak self] v, final in
            self?.change(String(localized: "Opacity"), final: final) { $0.opacity = v }
        })
    }

    private func fillControl(_ s: ToolSettings, modes: [ObjectStyle.FillMode], ellipse: Bool) -> NSView {
        let labels = [String(localized: "Outline"), String(localized: "Filled"), String(localized: "Outline with translucent fill")]
        return controls.segmented(images: modes.map { EditorIcons.fill($0, ellipse: ellipse) }, labels: Array(labels.prefix(modes.count)),
                                  selected: modes.firstIndex(of: s.fill) ?? 0) { [weak self] i in
            self?.change(String(localized: "Fill")) { $0.fill = modes[i] }
        }
    }

    static func title(_ style: ArrowStyle) -> String {
        switch style {
        case .straight: String(localized: "Straight")
        case .curved: String(localized: "Curved")
        case .tapered: String(localized: "Pointer")
        case .doubleHeaded: String(localized: "Double-headed")
        case .lineWithDot: String(localized: "Line with dot")
        }
    }
}
