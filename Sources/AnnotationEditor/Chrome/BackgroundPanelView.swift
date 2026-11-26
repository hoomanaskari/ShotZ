import AnnotationKit
import AppKit
import ShotzUI

/// G: the presentation background panel (SPEC §5.4), a sidebar beside the
/// canvas. Every control previews live; a slider drag is one undo step.
@MainActor final class BackgroundPanelView: NSView {
    private let model: EditorModel
    private let presets: BackgroundPresets
    private let controls = EditorControls()
    private let stack = NSStackView()
    private var rebuildScheduled = false
    static let width: CGFloat = 288

    init(model: EditorModel, presets: BackgroundPresets) {
        self.model = model
        self.presets = presets
        super.init(frame: NSRect(x: 0, y: 0, width: Self.width, height: 400))
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .withinWindow
        effect.translatesAutoresizingMaskIntoConstraints = false
        addSubview(effect)
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = ShotzUI.Space.s
        stack.edgeInsets = NSEdgeInsets(top: ShotzUI.Space.l, left: ShotzUI.Space.l, bottom: ShotzUI.Space.l, right: ShotzUI.Space.l)
        stack.translatesAutoresizingMaskIntoConstraints = false
        let flipped = FlippedView()
        flipped.translatesAutoresizingMaskIntoConstraints = false
        flipped.addSubview(stack)
        scroll.documentView = flipped
        addSubview(scroll)
        NSLayoutConstraint.activate([
            effect.leadingAnchor.constraint(equalTo: leadingAnchor), effect.trailingAnchor.constraint(equalTo: trailingAnchor),
            effect.topAnchor.constraint(equalTo: topAnchor), effect.bottomAnchor.constraint(equalTo: bottomAnchor),
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            flipped.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: flipped.leadingAnchor), stack.trailingAnchor.constraint(equalTo: flipped.trailingAnchor),
            stack.topAnchor.constraint(equalTo: flipped.topAnchor), stack.bottomAnchor.constraint(equalTo: flipped.bottomAnchor),
            widthAnchor.constraint(equalToConstant: Self.width),
        ])
        setAccessibilityLabel(String(localized: "Background"))
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    /// Refreshes after undo/redo or document changes made elsewhere.
    func scheduleRebuild() {
        guard !rebuildScheduled, !model.store.isInteractive else { return }
        rebuildScheduled = true
        DispatchQueue.main.async { [weak self] in
            self?.rebuildScheduled = false
            self?.rebuild()
        }
    }

    private var style: AnnotationKit.BackgroundStyle? { model.document.background }

    private func set(_ new: AnnotationKit.BackgroundStyle?, final: Bool = true) {
        model.setBackground(new, interactive: !final)
        if final {
            if model.store.isInteractive { model.store.commitInteractiveChange() }
            if let new { presets.last = new }
            scheduleRebuild()
        }
    }

    private func update(final: Bool = true, _ change: (inout AnnotationKit.BackgroundStyle) -> Void) {
        var s = style ?? presets.last
        change(&s)
        set(s, final: final)
    }

    // MARK: Build

    private func rebuild() {
        stack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        controls.reset()

        let title = EditorControls.panelTitle(String(localized: "Background"))
        let toggle = controls.panelSwitch(on: style != nil, label: String(localized: "Background on")) { [weak self] on in
            guard let self else { return }
            self.set(on ? self.presets.last : nil)
        }
        stack.addArrangedSubview(titleRow(title, toggle))

        guard let s = style else {
            stack.addArrangedSubview(EditorControls.note(String(localized: "Wraps the image in padding, a fill and a shadow for presenting."),
                                                         width: Self.contentWidth))
            return
        }
        divider()
        addFill(s)
        divider()
        let maxRadius = Double(model.unit * 24)
        let shadows = AnnotationKit.BackgroundStyle.Shadow.allCases
        let aspects = AnnotationKit.BackgroundStyle.Aspect.allCases
        form([
            .init(String(localized: "Padding"), controls.slider(
                value: s.padding * 100, min: 0, max: 25, width: Self.sliderWidth, label: String(localized: "Padding"), glyph: nil,
                format: { "\(Int($0.rounded()))%" }) { [weak self] v, final in
                self?.update(final: final) { $0.padding = v / 100 }
            }),
            .init(nil, controls.toggleChip(title: String(localized: "Auto-balance"), tooltip: String(localized: "Balance the margins around window shadows"),
                                           on: s.autoBalance) { [weak self] on in
                self?.update { $0.autoBalance = on }
            }),
            .init(String(localized: "Corners"), controls.slider(
                value: s.cornerRadius, min: 0, max: maxRadius, width: Self.sliderWidth, label: String(localized: "Corner radius"), glyph: nil,
                format: { "\(Int($0.rounded()))" }) { [weak self] v, final in
                self?.update(final: final) { $0.cornerRadius = v }
            }),
            .init(String(localized: "Shadow"), controls.segmented(
                titles: [String(localized: "Off"), String(localized: "Soft"), String(localized: "Strong")],
                selected: shadows.firstIndex(of: s.shadow), label: String(localized: "Shadow")) { [weak self] i in
                self?.update { $0.shadow = shadows[i] }
            }),
            .init(String(localized: "Aspect"), controls.segmented(
                titles: aspects.map { $0 == .auto ? String(localized: "Auto") : $0.rawValue },
                selected: aspects.firstIndex(of: s.aspect), label: String(localized: "Aspect")) { [weak self] i in
                self?.update { $0.aspect = aspects[i] }
            }),
            .init(String(localized: "Position"), Sized(alignmentGrid(s))),
        ])
        divider()
        addPresets(s)
    }

    /// Panel layout: a right-aligned label column and a control column (ShotzFormStack).
    static let labelWidth: CGFloat = 56
    static var contentWidth: CGFloat { width - 2 * ShotzUI.Space.l }
    static var sliderWidth: CGFloat { contentWidth - labelWidth - ShotzUI.Space.m - 56 }

    private func form(_ rows: [ShotzFormStack.Row]) {
        let f = ShotzFormStack(rows: rows, labelWidth: Self.labelWidth)
        f.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        stack.addArrangedSubview(f)
    }

    private func divider() {
        stack.addArrangedSubview(EditorControls.horizontalSeparator(width: Self.contentWidth))
    }

    private func addFill(_ s: AnnotationKit.BackgroundStyle) {
        let kind: Int = switch s.fill {
        case .none: 0
        case .solid: 1
        case .gradient: 2
        }
        let fill = ShotzFormStack.Row(String(localized: "Fill"), controls.segmented(
            titles: [String(localized: "None"), String(localized: "Colour"), String(localized: "Gradient")],
            selected: kind, label: String(localized: "Fill")) { [weak self] i in
            self?.update {
                switch i {
                case 0: $0.fill = .none
                case 1: $0.fill = .solid(RGBAColor(red: 0.93, green: 0.94, blue: 0.96))
                default: $0.fill = .gradient(BackgroundPresets.gradients[1])
                }
            }
        })
        switch s.fill {
        case .none:
            form([fill, .init(nil, EditorControls.caption(String(localized: "Transparent around the image")))])
        case .solid(let c):
            form([fill, .init(String(localized: "Colour"), controls.colorWell(NSColor(cgColor: c.cgColor) ?? .white, label: String(localized: "Fill colour")) { [weak self] color, final in
                self?.update(final: final) { $0.fill = .solid(Self.rgba(color)) }
            })])
        case .gradient(let g):
            form([fill])
            stack.addArrangedSubview(gradientGrid(selected: g))
            let from = controls.colorWell(NSColor(cgColor: g.from.cgColor) ?? .white, label: String(localized: "Gradient start")) { [weak self] color, final in
                self?.update(final: final) { if case .gradient(var gg) = $0.fill { gg.from = Self.rgba(color); $0.fill = .gradient(gg) } }
            }
            let to = controls.colorWell(NSColor(cgColor: g.to.cgColor) ?? .white, label: String(localized: "Gradient end")) { [weak self] color, final in
                self?.update(final: final) { if case .gradient(var gg) = $0.fill { gg.to = Self.rgba(color); $0.fill = .gradient(gg) } }
            }
            let wells = ShotzToolbarStack(groups: [[from, to]])
            wells.itemGap = ShotzUI.Space.s
            wells.showsSeparators = false
            form([
                .init(String(localized: "Colours"), wells),
                .init(String(localized: "Angle"), controls.slider(
                    value: g.angle, min: 0, max: 360, width: Self.sliderWidth, label: String(localized: "Gradient angle"), glyph: nil,
                    format: { "\(Int($0.rounded()))°" }) { [weak self] v, final in
                    self?.update(final: final) { if case .gradient(var gg) = $0.fill { gg.angle = v; $0.fill = .gradient(gg) } }
                }),
            ])
        }
    }

    private func gradientGrid(selected: AnnotationKit.BackgroundStyle.GradientFill) -> NSView {
        let tile = NSSize(width: (Self.contentWidth - 3 * 8) / 4, height: 30)
        let buttons: [NSButton] = GradientPreset.all.map { preset in
            let g = preset.fill
            let b = controls.imageButton(Self.gradientSwatch(g, selected: g == selected, size: tile), label: preset.name) { [weak self] in
                self?.update { $0.fill = .gradient(g) }
            }
            b.setAccessibilityRole(.radioButton)
            b.setAccessibilityValue(g == selected ? 1 : 0)
            return b
        }
        let rows = stride(from: 0, to: buttons.count, by: 4).map { Array(buttons[$0..<min($0 + 4, buttons.count)]) }
        let grid = NSGridView(views: rows)
        grid.rowSpacing = 8
        grid.columnSpacing = 8
        grid.setAccessibilityLabel(String(localized: "Gradient presets"))
        return grid
    }

    private func alignmentGrid(_ s: AnnotationKit.BackgroundStyle) -> NSView {
        let all = AnnotationKit.BackgroundStyle.Alignment.allCases
        let buttons: [NSButton] = all.map { a in
            let on = a == s.alignment
            let b = controls.imageButton(Self.alignmentChip(on: on), label: Self.alignmentName(a)) { [weak self] in self?.update { $0.alignment = a } }
            b.setAccessibilityRole(.radioButton)
            b.setAccessibilityValue(on ? 1 : 0)
            return b
        }
        let grid = NSGridView(views: [Array(buttons[0..<3]), Array(buttons[3..<6]), Array(buttons[6..<9])])
        grid.rowSpacing = 3
        grid.columnSpacing = 3
        grid.setContentHuggingPriority(.required, for: .horizontal)
        grid.setAccessibilityLabel(String(localized: "Image position"))
        return grid
    }

    /// A small rounded cell of the 3 × 3 position picker.
    static func alignmentChip(on: Bool) -> NSImage {
        NSImage(size: NSSize(width: 22, height: 15), flipped: true) { r in
            let p = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: ShotzUI.Radius.small, yRadius: ShotzUI.Radius.small)
            (on ? ShotzUI.Palette.accentFill : ShotzUI.Palette.surfaceSunken).setFill()
            p.fill()
            return true
        }
    }

    private func addPresets(_ s: AnnotationKit.BackgroundStyle) {
        let saved = presets.saved
        var titles = saved.map(\.name)
        if titles.isEmpty { titles = [String(localized: "None saved")] }
        // Show the preset the current background matches, if any.
        let current = saved.firstIndex { $0.style == s } ?? 0
        let popup = controls.popup(titles, selected: current, label: String(localized: "Saved presets")) { [weak self] i in
            guard let self, i < saved.count else { return }
            self.set(saved[i].style)
        }
        popup.isEnabled = !saved.isEmpty
        let save = controls.secondaryButton(String(localized: "Save…"), tooltip: String(localized: "Save…")) { [weak self] in self?.promptSave(s) }
        let delete = controls.secondaryButton(String(localized: "Delete…"), tooltip: String(localized: "Delete…")) { [weak self, weak popup] in
            guard let self, let i = popup?.selectedIndex, i >= 0, i < saved.count else { return }
            self.confirmDelete(saved[i].name)
        }
        delete.isEnabled = !saved.isEmpty
        delete.setAccessibilityLabel(String(localized: "Delete the selected preset"))
        let actions = ShotzToolbarStack(groups: [[save, delete]])
        actions.itemGap = ShotzUI.Space.s
        actions.showsSeparators = false
        form([.init(String(localized: "Presets"), popup), .init(nil, actions)])
    }

    private func confirmDelete(_ name: String) {
        guard let window else { return }
        let alert = NSAlert()
        alert.messageText = String(localized: "Delete the preset “\(name)”?")
        alert.informativeText = String(localized: "The current background is not changed.")
        alert.addButton(withTitle: String(localized: "Delete"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.presets.delete(name: name)
            self?.scheduleRebuild()
        }
    }

    private func promptSave(_ s: AnnotationKit.BackgroundStyle) {
        let alert = NSAlert()
        alert.messageText = String(localized: "Save Background Preset")
        alert.informativeText = String(localized: "Give the current background a name.")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 22))
        field.placeholderString = String(localized: "Preset name")
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Save"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.presets.save(s, name: field.stringValue)
            self?.scheduleRebuild()
        }
        alert.window.initialFirstResponder = field
    }

    // MARK: Helpers


    /// The title and the on/off chip at the trailing edge.
    private func titleRow(_ title: NSView, _ toggle: NSView) -> NSStackView {
        let spacer = NSView()
        spacer.setContentHuggingPriority(.init(1), for: .horizontal)
        let r = NSStackView(views: [title, spacer, toggle])
        r.orientation = .horizontal
        r.spacing = ShotzUI.Space.s
        r.alignment = .centerY
        r.widthAnchor.constraint(equalToConstant: Self.contentWidth).isActive = true
        return r
    }

    static func alignmentName(_ a: AnnotationKit.BackgroundStyle.Alignment) -> String {
        switch a {
        case .topLeft: String(localized: "Align top left")
        case .top: String(localized: "Align top")
        case .topRight: String(localized: "Align top right")
        case .left: String(localized: "Align left")
        case .center: String(localized: "Align centre")
        case .right: String(localized: "Align right")
        case .bottomLeft: String(localized: "Align bottom left")
        case .bottom: String(localized: "Align bottom")
        case .bottomRight: String(localized: "Align bottom right")
        }
    }

    static func rgba(_ color: NSColor) -> RGBAColor {
        let c = color.usingColorSpace(.sRGB) ?? .white
        return RGBAColor(red: c.redComponent, green: c.greenComponent, blue: c.blueComponent)
    }

    static func gradientSwatch(_ g: AnnotationKit.BackgroundStyle.GradientFill, selected: Bool,
                               size: NSSize = NSSize(width: 48, height: 30)) -> NSImage {
        NSImage(size: size, flipped: true) { r in
            let inner = r.insetBy(dx: 2, dy: 2)
            if let ctx = NSGraphicsContext.current?.cgContext {
                // The image is flipped (top-left), as AnnotationKit's fill expects.
                ctx.saveGState()
                ctx.addPath(CGPath(roundedRect: inner, cornerWidth: ShotzUI.Radius.small, cornerHeight: ShotzUI.Radius.small, transform: nil))
                ctx.clip()
                AnnotationRenderer.drawBackgroundFill(.gradient(g), in: inner, ctx: ctx)
                ctx.restoreGState()
            }
            if selected {
                ShotzUI.Palette.selectedBorder.setStroke()
                let ring = NSBezierPath(roundedRect: r.insetBy(dx: 0.75, dy: 0.75), xRadius: ShotzUI.Radius.small + 1.5, yRadius: ShotzUI.Radius.small + 1.5)
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }
}

final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}

/// Gives a grid its fitting size as its intrinsic size, so a form row can lay it out.
@MainActor final class Sized: NSView {
    private let content: NSView
    init(_ content: NSView) {
        self.content = content
        super.init(frame: NSRect(origin: .zero, size: content.fittingSize))
        content.frame = bounds
        addSubview(content)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: NSSize { content.fittingSize }
    override func layout() {
        super.layout()
        content.frame = bounds
    }
}
