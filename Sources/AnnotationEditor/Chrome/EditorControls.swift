import AppKit
import ShotzCore
import ShotzUI

/// Closure-backed target/action for AppKit controls.
@MainActor final class ControlAction: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// The one place the editor chrome creates its controls (toolbar, options bar, background
/// panel). Every control is a ShotzUI control sized and spaced with ShotzUI tokens; the few
/// ShotzUI does not have yet (number field, pop-up, panel switch) are standard AppKit controls
/// styled with ShotzUI tokens here, so they swap in one place when ShotzUI step 2 lands.
@MainActor final class EditorControls {
    private(set) var actions: [ControlAction] = []
    private var colorLinks: [ColorPanelLink] = []

    /// Options bar and panel controls share one height (28 pt).
    nonisolated static let size: ShotzUI.ControlSize = .regular

    func reset() {
        actions.removeAll()
        colorLinks.removeAll()
    }

    func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let a = ControlAction(handler)
        actions.append(a)
        control.target = a
        control.action = #selector(ControlAction.fire(_:))
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

    /// An on/off chip (Bold, Outline, Auto-balance).
    func toggleChip(title: String, glyph: EditorGlyph? = nil, tooltip: String, on: Bool,
                    _ handler: @escaping (Bool) -> Void) -> ShotzToggleChip {
        let c = ShotzToggleChip(title: title, icon: glyph.flatMap(EditorGlyphs.shotzIcon), isOn: on, size: Self.size)
        c.setShotzToolTip(tooltip)
        c.onToggle = handler
        return c
    }

    // MARK: Sliders

    /// Icon, track and value readout. `handler(value, isFinal)`: a drag is many updates and
    /// one final call when the mouse comes up (one undo step); keys give final values.
    func slider(value: Double, min: Double, max: Double, width: CGFloat = 80, label: String, glyph: EditorGlyph?,
                format: @escaping (Double) -> String, _ handler: @escaping (Double, Bool) -> Void) -> ShotzSlider {
        let range = min...Swift.max(max, min + 0.0001)
        let s = ShotzSlider(value: value, in: range, step: (range.upperBound - range.lowerBound) / 100,
                            icon: glyph.flatMap(EditorGlyphs.shotzIcon), label: label, size: Self.size)
        s.trackWidth = width
        s.format = format
        s.valuePlaceholder = [format(min), format(max), format((min + max) / 2)].max { $0.count < $1.count } ?? format(max)
        s.setShotzToolTip(label)
        var pending: Double?
        s.onChange = { v in
            handler(v, false)
            // The control tracks the drag in its own loop: this runs once the mouse is up
            // (or right after a key press) and settles the change into one undo step.
            let isFirst = pending == nil
            pending = v
            guard isFirst else { return }
            DispatchQueue.main.async {
                guard let last = pending else { return }
                pending = nil
                handler(last, true)
            }
        }
        return s
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded())) %" }

    // MARK: Buttons

    /// The one primary action of a surface.
    func primaryButton(_ title: String, glyph: EditorGlyph? = nil, tooltip: String, shortcut: String? = nil,
                       _ handler: @escaping () -> Void) -> ShotzButton {
        button(title, glyph: glyph, role: .primary, tooltip: tooltip, shortcut: shortcut, handler)
    }

    /// A labelled secondary action.
    func secondaryButton(_ title: String, glyph: EditorGlyph? = nil, tooltip: String, shortcut: String? = nil,
                         _ handler: @escaping () -> Void) -> ShotzButton {
        button(title, glyph: glyph, role: .secondary, tooltip: tooltip, shortcut: shortcut, handler)
    }

    /// A quiet icon-only action with a tooltip.
    func iconButton(_ glyph: EditorGlyph, label: String, tooltip: String, shortcut: String? = nil,
                    _ handler: @escaping (ShotzButton) -> Void) -> ShotzButton {
        let b = ShotzButton(icon: EditorGlyphs.shotzIcon(glyph), role: .quiet, size: Self.size)
        b.setAccessibilityLabel(label)
        b.setShotzToolTip(tooltip, shortcut: shortcut)
        b.onAction = { control in
            guard let button = control as? ShotzButton else { return }
            handler(button)
        }
        return b
    }

    private func button(_ title: String, glyph: EditorGlyph?, role: ShotzUI.ControlRole, tooltip: String, shortcut: String?,
                        _ handler: @escaping () -> Void) -> ShotzButton {
        let b = ShotzButton(title: title, icon: glyph.flatMap(EditorGlyphs.shotzIcon), role: role, size: Self.size)
        b.setShotzToolTip(tooltip, shortcut: shortcut)
        b.onAction = { _ in handler() }
        return b
    }

    /// Image tiles in the background panel (gradient presets, position grid): content, not chrome.
    func imageButton(_ image: NSImage, label: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(image: image, target: nil, action: nil)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.setAccessibilityLabel(label)
        b.setShotzToolTip(label)
        bind(b) { _ in handler() }
        return b
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

    /// A single colour (background fill, gradient stops): a custom well on its own.
    func colorWell(_ color: NSColor, label: String, _ handler: @escaping (NSColor, Bool) -> Void) -> ShotzSwatchRow {
        let row = ShotzSwatchRow(swatches: [], selectedIndex: 0, size: Self.size)
        row.customColor = color
        row.setAccessibilityLabel(label)
        row.setShotzToolTip(label)
        let link = ColorPanelLink(color: color) { [weak row] c, final in
            row?.customColor = c
            handler(c, final)
        }
        colorLinks.append(link)
        row.onSelect = { _ in link.open() }
        return row
    }

    // MARK: Not in ShotzUI step 1 yet: AppKit controls with ShotzUI tokens

    func numberField(_ value: Int, width: CGFloat = 56, label: String, _ handler: @escaping (Int) -> Void) -> NSTextField {
        let f = NSTextField(string: String(value))
        f.controlSize = .regular
        f.font = ShotzUI.Typography.value.font
        f.alignment = .right
        f.bezelStyle = .roundedBezel
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        f.formatter = formatter
        f.setAccessibilityLabel(label)
        f.setShotzToolTip(label)
        bind(f) { [weak self] field in
            handler(Int((field as? NSTextField)?.stringValue ?? "") ?? value)
            if NSApp.currentEvent?.type == .keyDown { self?.onFieldCommitted?() }
        }
        return f
    }

    /// Called after a number field commits, to hand the keyboard back to the canvas.
    var onFieldCommitted: (() -> Void)?

    func popup(_ titles: [String], selected: Int, label: String, _ handler: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .regular
        p.font = ShotzUI.Typography.label.font
        // Items carry their index as a tag; selection is read from the item, not its position.
        for (i, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = i
            p.menu?.addItem(item)
        }
        p.selectItem(withTag: selected)
        p.setAccessibilityLabel(label)
        p.setShotzToolTip(label)
        bind(p) { control in
            guard let tag = (control as? NSPopUpButton)?.selectedItem?.tag else { return }
            handler(tag)
        }
        return p
    }

    func panelSwitch(on: Bool, label: String, _ handler: @escaping (Bool) -> Void) -> NSSwitch {
        let s = NSSwitch()
        s.state = on ? .on : .off
        s.controlSize = .small
        s.setAccessibilityLabel(label)
        bind(s) { handler(($0 as? NSSwitch)?.state == .on) }
        return s
    }

    // MARK: Text and layout

    static func label(_ text: String, _ style: ShotzUI.Typography, color: NSColor = ShotzUI.Palette.textSecondary) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = style.font
        l.textColor = color
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }

    static func caption(_ text: String) -> NSTextField { label(text, .caption) }

    static func panelTitle(_ text: String) -> NSTextField { label(text, .title, color: ShotzUI.Palette.textPrimary) }

    static func formLabel(_ text: String, width: CGFloat) -> NSTextField {
        let l = label(text, .label)
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    static func note(_ text: String, width: CGFloat) -> NSTextField {
        let n = NSTextField(wrappingLabelWithString: text)
        n.font = ShotzUI.Typography.caption.font
        n.textColor = ShotzUI.Palette.textSecondary
        n.preferredMaxLayoutWidth = width
        return n
    }

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

    /// A brief confirmation bubble ("Copied", "Saved to Desktop").
    static func toast(_ text: String) -> NSView {
        let label = label(text, .control, color: ShotzUI.Palette.textPrimary)
        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = ShotzUI.Radius.card
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: ShotzUI.Space.l),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -ShotzUI.Space.l),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: ShotzUI.Space.s),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -ShotzUI.Space.s),
        ])
        return box
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
