import AnnotationKit
import AppKit
import ShotzUI

/// Context options under the tool strip. Shows the options of the selection
/// (restyling it) or of the active tool (setting its defaults).
///
/// Every tool's options are groups in a `ShotzToolbarStack`, in the order people change them
/// (colour, size, style, toggles, opacity). Each group has a priority. At the default window
/// width every group shows. When the window is narrower, the lowest-priority groups (the last
/// ones first) move into a quiet "More" button that opens them in a form popover, so a control
/// is never silently dropped.
@MainActor final class OptionsBarView: NSView {
    let model: EditorModel
    let controls = EditorControls()
    private var rebuildScheduled = false
    /// The crop tool's numeric fields and Apply/Cancel actions.
    var onCropApply: (() -> Void)?
    var onCropCancel: (() -> Void)?
    var onCropAspect: (() -> Void)?
    var onCropSize: ((CGFloat?, CGFloat?) -> Void)?
    /// Gives the keyboard back to the canvas (after Return in a number field).
    var onFocusCanvas: (() -> Void)?

    /// One group of the bar.
    struct Group {
        enum Priority: Int, Comparable {
            /// Overflows first (fine-tuning: opacity, corner radius, alignment).
            case low
            /// Overflows after the low ones (toggles).
            case medium
            /// Never overflows (colour, size, the tool's main style, crop size and actions).
            case essential
            static func < (a: Priority, b: Priority) -> Bool { a.rawValue < b.rawValue }
        }
        var title: String
        var view: NSView
        var priority: Priority
    }

    private(set) var groups: [Group] = []
    /// The groups currently moved into the More popover (in bar order).
    private(set) var overflow: [Group] = []
    private let stack = ShotzToolbarStack(groups: [])
    private(set) lazy var moreButton: ShotzButton = {
        let b = ShotzButton(title: String(localized: "More"), icon: .more, role: .quiet, size: EditorControls.size)
        b.setAccessibilityLabel(String(localized: "More options"))
        b.setShotzToolTip(String(localized: "More options"))
        b.onAction = { [weak self] _ in self?.showOverflow() }
        return b
    }()
    private var hint: NSTextField?
    private var popover: NSPopover?
    /// The More popover's content while it is shown (renders).
    var overflowView: NSView? { popover?.isShown == true ? popover?.contentViewController?.view : nil }

    static let insets = NSEdgeInsets(top: 0, left: ShotzUI.Space.l, bottom: 0, right: ShotzUI.Space.m)

    static let colorNames = [
        String(localized: "Red"), String(localized: "Orange"), String(localized: "Yellow"), String(localized: "Green"),
        String(localized: "Blue"), String(localized: "Purple"), String(localized: "Black"), String(localized: "White"),
    ]

    init(model: EditorModel) {
        self.model = model
        super.init(frame: .zero)
        stack.itemGap = ShotzUI.Space.xs
        addSubview(stack)
        controls.onFieldCommitted = { [weak self] in self?.onFocusCanvas?() }
        setAccessibilityElement(true)
        setAccessibilityRole(.toolbar)
        setAccessibilityLabel(String(localized: "Options"))
        model.observe { [weak self] event in
            switch event {
            case .tool, .selection: self?.scheduleRebuild()
            // Options changed elsewhere (keys 1–8, A cycling arrow styles): refresh.
            case .toolSettings where self?.applyingOwnChange == false: self?.scheduleRebuild()
            case .overlay where self?.model.toolKind == .crop: self?.updateCropFields()
            default: break
            }
        }
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    // Never widens the window: groups overflow into More instead.
    override var intrinsicContentSize: NSSize { NSSize(width: NSView.noIntrinsicMetric, height: EditorMetrics.barHeight) }

    func scheduleRebuild() {
        guard !rebuildScheduled else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuild()
        }
    }

    // MARK: Build

    private var applyingOwnChange = false
    var widthField: ShotzNumberField?
    var heightField: ShotzNumberField?

    func rebuild() {
        popover?.close()
        groups.removeAll()
        hint?.removeFromSuperview()
        hint = nil
        controls.reset()
        widthField = nil
        heightField = nil
        let s = model.displayedSettings
        let hasSelection = !model.selection.isEmpty

        if model.editingCounterID != nil {
            showHint(String(localized: "Type the number. Return finishes, Esc cancels."))
        } else if model.toolKind == .crop {
            addCropControls()
        } else if let kind = hasSelection ? model.optionsKind : model.toolKind {
            if kind == .select {
                showHint(String(localized: "Click to select, drag to select several, ⌘A selects all. Press a tool key to draw."))
            } else {
                addOptions(for: kind, s)
            }
        } else {
            // Mixed selection: the options every object shares.
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            addOpacity(s)
        }
        overflow = []
        stack.groups = groups.map { [$0.view] }
        needsLayout = true
    }

    private func showHint(_ text: String) {
        let l = EditorControls.caption(text)
        addSubview(l)
        hint = l
    }

    /// Adds a group to the bar.
    func add(_ v: NSView, _ title: String, priority: Group.Priority = .essential) {
        groups.append(Group(title: title, view: v, priority: priority))
    }

    /// Controls that sit together in one group (a caption and its field).
    static func row(_ views: [NSView]) -> NSView {
        let row = ShotzToolbarStack(groups: [views])
        row.itemGap = ShotzUI.Space.xs
        row.showsSeparators = false
        return row
    }

    // MARK: Layout and overflow

    private func width(of shown: [Group], more: Bool) -> CGFloat {
        let probe = shown.map { $0.view.intrinsicContentSize.width }.reduce(0, +)
            + CGFloat(max(shown.count - 1, 0)) * (2 * stack.groupGap + 1)
        return probe + (more ? 2 * stack.groupGap + 1 + moreButton.intrinsicContentSize.width : 0)
    }

    /// The groups that fit `available`: the lowest priority, latest first, overflow.
    func fitting(_ available: CGFloat) -> (shown: [Group], hidden: [Group]) {
        var shown = groups
        var hidden: [Group] = []
        while width(of: shown, more: !hidden.isEmpty) > available {
            let candidates = shown.indices.filter { shown[$0].priority < .essential }
            guard let drop = candidates.min(by: { a, b in
                shown[a].priority != shown[b].priority ? shown[a].priority < shown[b].priority : a > b
            }) else { break }
            hidden.append(shown.remove(at: drop))
        }
        let order = groups.map { ObjectIdentifier($0.view) }
        hidden.sort { order.firstIndex(of: ObjectIdentifier($0.view))! < order.firstIndex(of: ObjectIdentifier($1.view))! }
        return (shown, hidden)
    }

    override func layout() {
        super.layout()
        let i = Self.insets
        let available = bounds.width - i.left - i.right
        if let hint {
            let h = ceil(hint.intrinsicContentSize.height)
            hint.frame = CGRect(x: i.left, y: ((bounds.height - h) / 2).rounded(), width: max(available, 0), height: h)
        }
        let (shown, hidden) = fitting(available)
        if hidden.map({ ObjectIdentifier($0.view) }) != overflow.map({ ObjectIdentifier($0.view) }) {
            popover?.close()
            overflow = hidden
            let more: [[NSView]] = hidden.isEmpty ? [] : [[moreButton]]
            stack.groups = shown.map { [$0.view] } + more
        }
        let s = stack.intrinsicContentSize
        stack.frame = CGRect(x: i.left, y: ((bounds.height - s.height) / 2).rounded(), width: min(s.width, max(available, 0)), height: s.height)
    }

    /// The overflowed groups as a form in a popover under More.
    func showOverflow() {
        guard !overflow.isEmpty else { return }
        if let popover, popover.isShown { popover.close(); return }
        // A toggle chip names itself, so its row has no label.
        let form = ShotzFormStack(rows: overflow.map { .init($0.view is ShotzToggleChip ? nil : $0.title, $0.view) }, labelWidth: 72)
        let pad = ShotzUI.Space.l
        let size = form.intrinsicContentSize
        let host = NSView(frame: NSRect(x: 0, y: 0, width: size.width + 2 * pad, height: size.height + 2 * ShotzUI.Space.m))
        form.frame = NSRect(x: pad, y: ShotzUI.Space.m, width: size.width, height: size.height)
        host.addSubview(form)
        host.setAccessibilityLabel(String(localized: "More options"))
        let vc = NSViewController()
        vc.view = host
        let p = NSPopover()
        p.behavior = .transient
        p.contentViewController = vc
        p.contentSize = host.frame.size
        popover = p
        p.show(relativeTo: moreButton.bounds, of: moreButton, preferredEdge: .maxY)
        // Overflowed controls live in the form while it is open; when they fit again the
        // bar takes them back (re-adding moves them out of the form).
    }

    private func addOptions(for kind: ToolKind, _ s: ToolSettings) {
        switch kind {
        case .arrow:
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            add(controls.segmented(glyphs: ArrowStyle.allCases.map { .arrowStyle($0) }, labels: ArrowStyle.allCases.map(Self.title),
                                   selected: ArrowStyle.allCases.firstIndex(of: s.arrowStyle), label: String(localized: "Arrow style")) { [weak self] i in
                self?.change(String(localized: "Arrow Style")) { $0.arrowStyle = ArrowStyle.allCases[i] }
            }, String(localized: "Style"))
            add(controls.toggleChip(title: String(localized: "Outline"), tooltip: String(localized: "Contrast outline around the arrow"),
                                    on: s.contrastOutline) { [weak self] on in
                self?.change(String(localized: "Outline")) { $0.contrastOutline = on }
            }, String(localized: "Outline"), priority: .medium)
            addOpacity(s)
        case .rectangle:
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            add(fillControl(s, modes: [.outline, .filled, .outlineTranslucentFill], ellipse: false), String(localized: "Fill"))
            add(controls.slider(value: s.cornerRadiusUnits, min: 0, max: 12, width: 64, label: String(localized: "Corner radius"),
                                glyph: .cornerRadius, format: { "\(Int($0.rounded()))" }) { [weak self] v, final in
                self?.change(String(localized: "Corner Radius"), final: final) { $0.cornerRadiusUnits = v }
            }, String(localized: "Corners"), priority: .low)
            addOpacity(s)
        case .ellipse:
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            add(fillControl(s, modes: [.outline, .filled], ellipse: true), String(localized: "Fill"))
            addOpacity(s)
        case .line:
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            let dashes = ObjectStyle.Dash.allCases
            add(controls.segmented(glyphs: dashes.map { .dash($0) }, labels: [String(localized: "Solid"), String(localized: "Dashed")],
                                   selected: dashes.firstIndex(of: s.dash), label: String(localized: "Line style")) { [weak self] i in
                self?.change(String(localized: "Line Style")) { $0.dash = dashes[i] }
            }, String(localized: "Style"))
            addOpacity(s)
        case .text:
            addTextOptions(s)
        case .highlighter:
            addColors(s)
            add(controls.segmented(
                glyphs: [.highlightFreehand, .highlightRect],
                labels: [String(localized: "Freehand marker"), String(localized: "Rectangle highlight")],
                selected: s.highlightRect ? 1 : 0, label: String(localized: "Highlighter shape")
            ) { [weak self] i in
                self?.change(String(localized: "Highlighter")) { $0.highlightRect = i == 1 }
            }, String(localized: "Shape"))
            add(thickness(s), String(localized: "Thickness"))
            addOpacity(s)
        case .redact:
            addRedactOptions(s)
        case .counter:
            addColors(s)
            add(controls.segmented(titles: ["S", "M", "L", "XL"], selected: s.sizeStep, label: String(localized: "Counter size")) { [weak self] i in
                self?.change(String(localized: "Counter Size")) { $0.sizeStep = i }
            }, String(localized: "Size"))
            add(controls.segmented(titles: ["1 2 3", "A B C"], selected: s.counterNumbering == .numeric ? 0 : 1,
                                   label: String(localized: "Numbering")) { [weak self] i in
                self?.change(String(localized: "Numbering")) { $0.counterNumbering = i == 0 ? .numeric : .alphabetic }
            }, String(localized: "Numbering"), priority: .medium)
            let start = controls.numberField(s.counterStart, in: 1...999, label: String(localized: "Start value")) { [weak self] v in
                self?.model.library.update(.counter) { $0.counterStart = max(1, v) }
            }
            add(Self.row([EditorControls.caption(String(localized: "Start at")), start]), String(localized: "Start at"), priority: .medium)
        case .pen:
            addColors(s)
            add(thickness(s), String(localized: "Thickness"))
            addOpacity(s)
        case .select, .crop:
            break
        }
    }

    // MARK: Pieces

    /// - rebuild: false keeps the controls (the colour well must survive, or the
    ///   colour panel detaches from it).
    func change(_ name: String, final: Bool = true, rebuild: Bool = true, _ apply: @escaping (inout ToolSettings) -> Void) {
        if !final, !model.selection.isEmpty, !model.store.isInteractive {
            model.store.beginInteractiveChange(name)
        }
        applyingOwnChange = true
        model.changeOption(name, apply)
        applyingOwnChange = false
        if final {
            if model.store.isInteractive { model.store.commitInteractiveChange() }
            if rebuild { scheduleRebuild() }
        }
    }

    func addColors(_ s: ToolSettings) {
        let presets = RGBAColor.presets.map { NSColor(cgColor: $0.cgColor) ?? .red }
        let preset = RGBAColor.presets.firstIndex(of: s.color)
        let row = controls.colorRow(
            presets: presets, names: Self.colorNames, selectedPreset: preset,
            customColor: preset == nil ? NSColor(cgColor: s.color.cgColor) : nil,
            onPreset: { [weak self] i in
                self?.change(String(localized: "Colour")) { $0.color = RGBAColor.presets[i] }
            },
            onCustom: { [weak self] color, final in
                guard let srgb = color.usingColorSpace(.sRGB) else { return }
                let c = RGBAColor(red: srgb.redComponent, green: srgb.greenComponent, blue: srgb.blueComponent)
                // Keep the row (the colour panel stays linked to it) while the colour changes.
                self?.change(String(localized: "Colour"), final: final, rebuild: false) { $0.color = c }
            })
        add(row, String(localized: "Colour"))
    }

    /// ShotzUI's stepped thickness picker.
    private func thickness(_ s: ToolSettings) -> NSView {
        let c = ShotzSegmentedControl.thicknessPicker(selected: s.thicknessStep, size: EditorControls.size)
        c.setShotzToolTip(String(localized: "Thickness"))
        c.onChange = { [weak self] i in
            self?.change(String(localized: "Thickness")) { $0.thicknessStep = i }
        }
        return c
    }

    func addOpacity(_ s: ToolSettings) {
        add(controls.slider(value: s.opacity, min: 0.1, max: 1, width: 88, label: String(localized: "Opacity"),
                            glyph: .opacity, format: EditorControls.percent) { [weak self] v, final in
            self?.change(String(localized: "Opacity"), final: final) { $0.opacity = v }
        }, String(localized: "Opacity"), priority: .low)
    }

    private func fillControl(_ s: ToolSettings, modes: [ObjectStyle.FillMode], ellipse: Bool) -> NSView {
        let labels = [String(localized: "Outline"), String(localized: "Filled"), String(localized: "Outline with translucent fill")]
        return controls.segmented(glyphs: modes.map { .fill($0, ellipse: ellipse) }, labels: Array(labels.prefix(modes.count)),
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
