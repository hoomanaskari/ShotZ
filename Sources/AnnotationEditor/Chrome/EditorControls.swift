import AppKit
import ShotzCore
import ShotzUI

/// The one place the editor chrome creates its controls (toolbar, options bar, background
/// panel, action bar). Every control is a ShotzUI control, sized and spaced with ShotzUI tokens.
@MainActor final class EditorControls {
    private var colorLinks: [ColorPanelLink] = []

    /// Options bar and panel controls: compact chrome (24 pt) on a 28-pt hit row, as in
    /// ShotzUI's `EditorOptionsBar` reference.
    nonisolated static let size: ShotzUI.ControlSize = .compact
    /// The action bar uses regular controls (28 pt), as in ShotzUI's `EditorActionArea`.
    nonisolated static let actionSize: ShotzUI.ControlSize = .regular

    func reset() {
        colorLinks.removeAll()
    }

    // MARK: Pickers and chips

    /// A style picker of icon segments (per-segment VoiceOver from ShotzUI).
    func segmented(glyphs: [EditorGlyph], labels: [String], selected: Int?, label: String? = nil,
                   _ handler: @escaping (Int) -> Void) -> ShotzSegmentedControl {
        let segments = glyphs.map { g -> ShotzSegmentedControl.Segment in
            EditorGlyphs.shotzIcon(g).map { .init(icon: $0) } ?? .init(title: "?")
        }
        let c = ShotzSegmentedControl(segments: segments, selectedIndex: selected ?? 0, size: Self.size)
        c.setAccessibilityLabel(label ?? labels.joined(separator: ", "))
        c.setShotzToolTip(labels.joined(separator: " · "))
        c.onChange = handler
        return c
    }

    func segmented(titles: [String], selected: Int?, label: String? = nil, _ handler: @escaping (Int) -> Void) -> ShotzSegmentedControl {
        let c = ShotzSegmentedControl(segments: titles.map { .init(title: $0) }, selectedIndex: selected ?? 0, size: Self.size)
        if let label {
            c.setAccessibilityLabel(label)
            c.setShotzToolTip(label)
        }
        c.onChange = handler
        return c
    }

    /// An on/off chip with a title (Outline).
    func toggleChip(title: String, tooltip: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> ShotzToggleChip {
        let c = ShotzToggleChip(title: title, isOn: on, size: Self.size)
        c.setShotzToolTip(tooltip)
        c.onToggle = handler
        return c
    }

    /// An icon-only on/off chip for tight bars (Bold).
    func toggleChip(glyph: EditorGlyph, label: String, shortcut: String? = nil, on: Bool, _ handler: @escaping (Bool) -> Void) -> ShotzToggleChip {
        let c = ShotzToggleChip(icon: EditorGlyphs.shotzIcon(glyph) ?? .check, label: label, isOn: on, size: Self.size)
        c.setShotzToolTip(label, shortcut: shortcut)
        c.onToggle = handler
        return c
    }

    // MARK: Sliders

    /// Icon, track and value readout. `handler(value, isFinal)`: a drag is many live updates and
    /// one final call when the mouse comes up (one undo step); keys give final values.
    /// The final call comes from the slider at mouse-up, never from a main-queue hop: queued work
    /// runs during the drag (inside AppKit's event tracking), and a final mid-drag rebuilt the
    /// panel under the pointer (the 0.1.1 "slider jumps to the end" bug).
    func slider(value: Double, min: Double, max: Double, width: CGFloat = 80, label: String, glyph: EditorGlyph?,
                format: @escaping (Double) -> String, _ handler: @escaping (Double, Bool) -> Void) -> ShotzSlider {
        let range = min...Swift.max(max, min + 0.0001)
        let s = ShotzSlider(value: value, in: range, step: (range.upperBound - range.lowerBound) / 100,
                            icon: glyph.flatMap(EditorGlyphs.shotzIcon), label: label, size: Self.size)
        s.trackWidth = width
        s.format = format
        s.valuePlaceholder = [format(min), format(max), format((min + max) / 2)].max { $0.count < $1.count } ?? format(max)
        s.setShotzToolTip(label)
        s.onChange = { v in handler(v, false) }
        s.onCommit = { v in handler(v, true) }
        return s
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    // MARK: Buttons

    /// The one primary action of a surface.
    func primaryButton(_ title: String, glyph: EditorGlyph? = nil, tooltip: String, shortcut: String? = nil,
                       size: ShotzUI.ControlSize = EditorControls.size, _ handler: @escaping () -> Void) -> ShotzButton {
        button(title, glyph: glyph, role: .primary, tooltip: tooltip, shortcut: shortcut, size: size, handler)
    }

    /// A labelled secondary action.
    func secondaryButton(_ title: String, glyph: EditorGlyph? = nil, tooltip: String, shortcut: String? = nil,
                         size: ShotzUI.ControlSize = EditorControls.size, _ handler: @escaping () -> Void) -> ShotzButton {
        button(title, glyph: glyph, role: .secondary, tooltip: tooltip, shortcut: shortcut, size: size, handler)
    }

    /// A quiet icon-only action with a tooltip.
    func iconButton(_ glyph: EditorGlyph, label: String, tooltip: String, shortcut: String? = nil,
                    size: ShotzUI.ControlSize = EditorControls.size, _ handler: @escaping (ShotzButton) -> Void) -> ShotzButton {
        let b = ShotzButton(icon: EditorGlyphs.shotzIcon(glyph), role: .quiet, size: size)
        b.setAccessibilityLabel(label)
        b.setShotzToolTip(tooltip, shortcut: shortcut)
        b.onAction = { control in
            guard let button = control as? ShotzButton else { return }
            handler(button)
        }
        return b
    }

    private func button(_ title: String, glyph: EditorGlyph?, role: ShotzUI.ControlRole, tooltip: String, shortcut: String?,
                        size: ShotzUI.ControlSize, _ handler: @escaping () -> Void) -> ShotzButton {
        let b = ShotzButton(title: title, icon: glyph.flatMap(EditorGlyphs.shotzIcon), role: role, size: size)
        b.setShotzToolTip(tooltip, shortcut: shortcut)
        b.onAction = { _ in handler() }
        return b
    }

    /// Image tiles (gradient presets, image position): a ShotzTileButton with the selection ring.
    func tile(_ image: NSImage, size: CGSize, label: String, selected: Bool, _ handler: @escaping () -> Void) -> ShotzTileButton {
        let t = ShotzTileButton(image: image, size: size, label: label)
        t.isSelected = selected
        t.setShotzToolTip(label)
        t.onAction = { _ in handler() }
        return t
    }

    /// Content for a ShotzTileButton, drawn with a top-left origin.
    static func tileImage(size: CGSize, _ draw: @escaping (CGContext, CGRect) -> Void) -> NSImage {
        NSImage(size: size, flipped: true) { r in
            if let ctx = NSGraphicsContext.current?.cgContext { draw(ctx, r) }
            return true
        }
    }

    /// Picks a colour from anywhere on screen (the system colour sampler).
    func eyedropper(_ handler: @escaping @MainActor (NSColor) -> Void) -> ShotzButton {
        iconButton(.eyedropper, label: String(localized: "Pick colour from screen"), tooltip: String(localized: "Pick colour from screen")) { _ in
            NSColorSampler().show { color in
                guard let color else { return }
                MainActor.assumeIsolated { handler(color) }
            }
        }
    }

    // MARK: Colour

    /// The preset swatches with the custom-colour well (ShotzSwatchRow). `onPreset(index)`;
    /// `onCustom(colour, isFinal)` from the colour panel opened by the well.
    func colorRow(presets: [NSColor], names: [String], selectedPreset: Int?, customColor: NSColor?,
                  onPreset: @escaping (Int) -> Void, onCustom: @escaping (NSColor, Bool) -> Void) -> ShotzSwatchRow {
        let row = ShotzSwatchRow(swatches: zip(presets, names).map { .init($0, name: $1) },
                                 selectedIndex: selectedPreset ?? (customColor != nil ? presets.count : nil), size: Self.size)
        row.customColor = customColor
        row.setShotzToolTip(String(localized: "Colour  1–8"))
        let link = ColorPanelLink(color: customColor ?? .systemRed) { [weak row] color, final in
            row?.customColor = color
            row?.selectedIndex = presets.count
            onCustom(color, final)
        }
        colorLinks.append(link)
        row.onSelect = { i in
            if i < presets.count { onPreset(i) } else { link.open() }
        }
        return row
    }

    /// A single colour (background fill, gradient stops): a ShotzColorWell opening the colour panel.
    func colorWell(_ color: NSColor, label: String, _ handler: @escaping (NSColor, Bool) -> Void) -> ShotzColorWell {
        let well = ShotzColorWell(color: color, showsHueRing: false, label: label)
        well.setShotzToolTip(label)
        let link = ColorPanelLink(color: color) { [weak well] c, final in
            well?.color = c
            handler(c, final)
        }
        colorLinks.append(link)
        well.onAction = { _ in link.open() }
        return well
    }

    // MARK: Fields and menus

    func numberField(_ value: Int, in range: ClosedRange<Int> = 1...99_999, label: String,
                     _ handler: @escaping (Int) -> Void) -> ShotzNumberField {
        let f = ShotzNumberField(value: Double(value), in: Double(range.lowerBound)...Double(range.upperBound), step: 1, label: label, size: Self.size)
        f.digits = max(String(range.upperBound).count, 2)
        f.setShotzToolTip(label)
        f.onChange = { [weak self] v in
            handler(Int(v.rounded()))
            if NSApp.currentEvent?.type == .keyDown { self?.onFieldCommitted?() }
        }
        return f
    }

    /// Called after a number field commits with Return, to hand the keyboard back to the canvas.
    var onFieldCommitted: (() -> Void)?

    /// A choice pop-up (the selection is read from the item, never its position).
    func popup(_ titles: [String], selected: Int, label: String, _ handler: @escaping (Int) -> Void) -> ShotzPopUpButton {
        let p = ShotzPopUpButton(items: titles, selectedIndex: selected, size: Self.size)
        p.setAccessibilityLabel(label)
        p.setShotzToolTip(label)
        p.onChange = handler
        return p
    }

    /// A quiet pop-up that shows `title` and opens `menu` (zoom value, More options).
    func menuButton(title: String?, glyph: EditorGlyph?, menu: NSMenu, label: String, tooltip: String, shortcut: String? = nil,
                    size: ShotzUI.ControlSize = EditorControls.size) -> ShotzPopUpButton {
        let p = ShotzPopUpButton(items: [title ?? ""], selectedIndex: 0, icon: glyph.flatMap(EditorGlyphs.shotzIcon), role: .quiet, size: size)
        p.actionMenu = menu
        p.setAccessibilityLabel(label)
        p.setShotzToolTip(tooltip, shortcut: shortcut)
        return p
    }

    /// A panel's on/off.
    func panelSwitch(on: Bool, label: String, shortcut: String? = nil, _ handler: @escaping (Bool) -> Void) -> ShotzSwitch {
        let sw = ShotzSwitch(isOn: on, label: label)
        sw.setShotzToolTip(label, shortcut: shortcut)
        sw.onToggle = handler
        return sw
    }

    /// An on/off setting inside a panel (Auto-balance).
    func checkbox(_ title: String, tooltip: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> ShotzCheckbox {
        let c = ShotzCheckbox(title, isOn: on)
        c.setShotzToolTip(tooltip)
        c.onToggle = handler
        return c
    }

    // MARK: Text and layout

    static func caption(_ text: String) -> NSTextField { ShotzUI.label(text, .caption) }
    static func panelTitle(_ text: String) -> NSTextField { ShotzUI.label(text, .panelTitle) }
    static func note(_ text: String, width: CGFloat) -> NSTextField { ShotzUI.label(text, .note, width: width) }

    static func separator(length: CGFloat = 20) -> NSView {
        let s = ShotzSeparator(.vertical)
        s.length = length
        return s
    }

    static func horizontalSeparator(width: CGFloat) -> NSView {
        let s = ShotzSeparator(.horizontal)
        s.length = width
        return s
    }

    // MARK: Feedback

    /// A brief confirmation ("Copied", "Saved to Desktop").
    static func toast(_ text: String, in view: NSView, success: Bool = true) {
        ShotzToast(text, tone: success ? .success : .failure).show(in: view)
    }
}

/// Bridges a colour well to the shared colour panel: live preview, one settled change.
@MainActor final class ColorPanelLink: NSObject {
    private var color: NSColor
    private let onChange: (NSColor, Bool) -> Void
    private var settle: DispatchWorkItem?

    init(color: NSColor, onChange: @escaping (NSColor, Bool) -> Void) {
        self.color = color
        self.onChange = onChange
    }

    func open() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(changed(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func changed(_ panel: NSColorPanel) {
        color = panel.color
        onChange(color, false)
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange(self.color, true)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}
