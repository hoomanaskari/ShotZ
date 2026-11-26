import AppKit

/// Closure-backed target/action for AppKit controls.
@MainActor final class ControlAction: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// The one place the editor chrome creates its controls (toolbar, options bar, background
/// panel). Every surface asks this factory, so the whole chrome can move to the shared
/// ShotzUI controls by changing only this type.
@MainActor final class EditorControls {
    private(set) var actions: [ControlAction] = []

    func reset() { actions.removeAll() }

    func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let a = ControlAction(handler)
        actions.append(a)
        control.target = a
        control.action = #selector(ControlAction.fire(_:))
    }

    /// A style picker: glyph segments with tooltips and per-segment VoiceOver labels.
    func segmented(
        images: [NSImage], labels: [String], selected: Int?, label: String? = nil, _ handler: @escaping (Int) -> Void
    ) -> GlyphSegmentedControl {
        let segments = zip(images, labels).map { GlyphSegmentedControl.Segment(image: $0, title: nil, label: $1, shortcut: nil) }
        let c = GlyphSegmentedControl(style: .options, segments: segments, selected: selected,
                                      label: label ?? labels.joined(separator: ", "))
        c.onSelect = handler
        return c
    }

    func segmented(titles: [String], selected: Int?, label: String? = nil, _ handler: @escaping (Int) -> Void) -> GlyphSegmentedControl {
        let segments = titles.map { GlyphSegmentedControl.Segment(image: nil, title: $0, label: $0, shortcut: nil) }
        let c = GlyphSegmentedControl(style: .options, segments: segments, selected: selected, label: label ?? titles.joined(separator: ", "))
        c.onSelect = handler
        return c
    }

    /// A one-glyph on/off chip in the same style as the pickers.
    func toggleChip(_ glyph: EditorGlyph, label: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> GlyphSegmentedControl {
        let c = GlyphSegmentedControl(style: .options,
                                      segments: [.init(image: EditorGlyphs.image(glyph, label: label), title: nil, label: label, shortcut: nil)],
                                      selected: on ? 0 : nil, label: label)
        c.setAccessibilityRole(.checkBox)
        var state = on
        c.onSelect = { [weak c] _ in
            state.toggle()
            c?.selectedIndex = state ? 0 : nil
            handler(state)
        }
        return c
    }

    /// A labelled on/off chip ("Outline") in the picker style.
    func toggleChip(title: String, label: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> GlyphSegmentedControl {
        let c = GlyphSegmentedControl(style: .options, segments: [.init(image: nil, title: title, label: label, shortcut: nil)],
                                      selected: on ? 0 : nil, label: label)
        c.setAccessibilityRole(.checkBox)
        var state = on
        c.onSelect = { [weak c] _ in
            state.toggle()
            c?.selectedIndex = state ? 0 : nil
            handler(state)
        }
        return c
    }

    /// Glyph, slider and value readout in one row.
    func sliderRow(
        value: Double, min: Double, max: Double, width: CGFloat = 80, label: String, glyph: EditorGlyph?,
        format: @escaping (Double) -> String, _ handler: @escaping (Double, Bool) -> Void
    ) -> ValueSliderRow {
        weak var rowRef: ValueSliderRow?
        let s = slider(value: value, min: min, max: max, width: width, label: label) { v, final in
            handler(v, final)
            rowRef?.refresh()
        }
        let row = ValueSliderRow(glyph: glyph, label: label, slider: s, width: width, format: format)
        rowRef = row
        return row
    }

    static func percent(_ v: Double) -> String { "\(Int((v * 100).rounded()))%" }

    /// `handler(value, isFinal)`: isFinal on mouse up (one undo step per drag).
    func slider(
        value: Double, min: Double, max: Double, width: CGFloat = 90, label: String,
        _ handler: @escaping (Double, Bool) -> Void
    ) -> NSSlider {
        let s = NSSlider(value: value, minValue: min, maxValue: max, target: nil, action: nil)
        s.controlSize = .small
        s.isContinuous = true
        s.widthAnchor.constraint(equalToConstant: width).isActive = true
        s.setAccessibilityLabel(label)
        s.toolTip = label
        bind(s) { control in
            let isFinal = NSApp.currentEvent.map { $0.type == .leftMouseUp || $0.type == .keyDown } ?? true
            handler(control.doubleValue, isFinal)
        }
        return s
    }

    func checkbox(_ title: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        b.controlSize = .small
        b.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        b.state = on ? .on : .off
        bind(b) { handler(($0 as? NSButton)?.state == .on) }
        return b
    }


    func imageButton(_ image: NSImage, label: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(image: image, target: nil, action: nil)
        b.isBordered = false
        b.imagePosition = .imageOnly
        b.setAccessibilityLabel(label)
        b.toolTip = label
        bind(b) { _ in handler() }
        return b
    }

    func prominentButton(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = ProminentButton(title: title, image: nil, target: nil, action: nil, height: 22)
        bind(b) { _ in handler() }
        return b
    }

    func button(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.controlSize = .regular
        b.bezelStyle = .push
        bind(b) { _ in handler() }
        return b
    }

    func popup(_ titles: [String], selected: Int, label: String, _ handler: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        // Items carry their index as a tag; selection is read from the item, not its position.
        for (i, title) in titles.enumerated() {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            item.tag = i
            p.menu?.addItem(item)
        }
        p.selectItem(withTag: selected)
        p.setAccessibilityLabel(label)
        p.toolTip = label
        bind(p) { control in
            guard let tag = (control as? NSPopUpButton)?.selectedItem?.tag else { return }
            handler(tag)
        }
        return p
    }

    /// Called after a number field commits, to hand the keyboard back to the canvas.
    var onFieldCommitted: (() -> Void)?

    func numberField(_ value: Int, width: CGFloat = 54, label: String, _ handler: @escaping (Int) -> Void) -> NSTextField {
        let f = NSTextField(string: String(value))
        f.controlSize = .small
        f.bezelStyle = .roundedBezel
        f.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        f.formatter = formatter
        f.setAccessibilityLabel(label)
        f.toolTip = label
        bind(f) { [weak self] field in
            handler(Int((field as? NSTextField)?.stringValue ?? "") ?? value)
            // Return in the field: back to the canvas so tool keys work again.
            if NSApp.currentEvent?.type == .keyDown { self?.onFieldCommitted?() }
        }
        return f
    }

    func colorWell(_ color: NSColor, isCustom: Bool = true, label: String, _ handler: @escaping (NSColor, Bool) -> Void) -> CustomColorWell {
        let w = CustomColorWell(color: color, isCustom: isCustom, label: label)
        w.onChange = handler
        return w
    }

    static func caption(_ text: String) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.lineBreakMode = .byTruncatingTail
        l.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return l
    }


    static func separator() -> NSView {
        let v = NSBox()
        v.boxType = .custom
        v.borderWidth = 0
        v.fillColor = .separatorColor
        v.translatesAutoresizingMaskIntoConstraints = false
        v.heightAnchor.constraint(equalToConstant: 18).isActive = true
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}
