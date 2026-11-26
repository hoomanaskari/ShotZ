import AppKit

/// A picker whose selection the chrome sets from outside (tool strip, toggles).
@MainActor protocol SegmentedPicker: NSView {
    var selectedIndex: Int? { get set }
}

extension GlyphSegmentedControl: SegmentedPicker {}

/// Toolbar, colour and panel controls.
extension EditorControls {
    // MARK: Toolbar

    struct ToolItem {
        var glyph: EditorGlyph
        var label: String
        var shortcut: String
    }

    /// The tool strip: one selected tool, groups split by dividers.
    func toolStrip(_ items: [ToolItem], selected: Int?, groupStarts: Set<Int>, label: String,
                   _ onSelect: @escaping (Int) -> Void) -> any SegmentedPicker {
        let segments = items.map {
            GlyphSegmentedControl.Segment(image: EditorGlyphs.image($0.glyph, size: 18, label: $0.label), title: nil,
                                          label: $0.label, shortcut: $0.shortcut)
        }
        let strip = GlyphSegmentedControl(style: .tools, segments: segments, selected: selected, label: label)
        strip.groupStarts = groupStarts
        strip.onSelect = onSelect
        return strip
    }

    /// An on/off panel switch in the toolbar (distinct from a selected tool).
    func toolbarToggle(_ item: ToolItem, on: Bool, _ onToggle: @escaping () -> Void) -> any SegmentedPicker {
        let toggle = GlyphSegmentedControl(
            style: .toggle,
            segments: [.init(image: EditorGlyphs.image(item.glyph, size: 18, label: item.label), title: nil,
                             label: item.label, shortcut: item.shortcut)],
            selected: on ? 0 : nil, label: item.label)
        toggle.setAccessibilityRole(.checkBox)
        toggle.onSelect = { _ in onToggle() }
        return toggle
    }

    /// The one primary action (accent).
    func primaryButton(_ title: String, glyph: EditorGlyph?, tooltip: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = ProminentButton(title: title, image: glyph.map { EditorGlyphs.image($0, size: 16, label: title) }, target: nil, action: nil)
        b.toolTip = tooltip
        bind(b) { _ in handler() }
        return b
    }

    /// A secondary action with a title.
    func secondaryButton(_ title: String, glyph: EditorGlyph?, tooltip: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, image: glyph.map { EditorGlyphs.image($0, size: 16, label: title) } ?? NSImage(), target: nil, action: nil)
        if glyph == nil { b.image = nil }
        b.bezelStyle = .push
        b.controlSize = .large
        b.imagePosition = glyph == nil ? .noImage : .imageLeading
        b.imageHugsTitle = true
        b.font = .systemFont(ofSize: NSFont.systemFontSize, weight: .medium)
        b.toolTip = tooltip
        b.setAccessibilityLabel(title)
        bind(b) { _ in handler() }
        return b
    }

    /// An icon-only action with a tooltip and a full-size hit target.
    func iconButton(_ glyph: EditorGlyph, label: String, tooltip: String, _ handler: @escaping (NSButton) -> Void) -> NSButton {
        let b = NSButton(image: EditorGlyphs.image(glyph, size: 16, label: label), target: nil, action: nil)
        b.bezelStyle = .push
        b.controlSize = .large
        b.imagePosition = .imageOnly
        b.widthAnchor.constraint(equalToConstant: 36).isActive = true
        b.toolTip = tooltip
        b.setAccessibilityLabel(label)
        bind(b) { control in
            guard let button = control as? NSButton else { return }
            handler(button)
        }
        return b
    }

    /// The zoom menu (a pull-down whose title shows the zoom).
    static func zoomMenu() -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: true)
        p.controlSize = .small
        p.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        p.bezelStyle = .flexiblePush
        p.isBordered = false
        p.setAccessibilityLabel(String(localized: "Zoom"))
        return p
    }

    // MARK: Colour

    func swatch(_ color: NSColor, selected: Bool, label: String, _ handler: @escaping () -> Void) -> ColorSwatchControl {
        ColorSwatchControl(color: color, selected: selected, label: label, handler: handler)
    }

    func eyedropper(label: String, _ onPick: @escaping (NSColor) -> Void) -> NSView {
        let b = EyedropperButton(label: label)
        b.onPick = onPick
        return b
    }

    // MARK: Panel

    func panelSwitch(on: Bool, label: String, _ handler: @escaping (Bool) -> Void) -> NSSwitch {
        let s = NSSwitch()
        s.state = on ? .on : .off
        s.controlSize = .small
        s.setAccessibilityLabel(label)
        bind(s) { handler(($0 as? NSSwitch)?.state == .on) }
        return s
    }

    static func panelTitle(_ text: String) -> NSTextField {
        let t = NSTextField(labelWithString: text)
        t.font = .systemFont(ofSize: NSFont.systemFontSize + 1, weight: .semibold)
        return t
    }

    static func formLabel(_ text: String, width: CGFloat) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        l.textColor = .secondaryLabelColor
        l.alignment = .right
        l.widthAnchor.constraint(equalToConstant: width).isActive = true
        return l
    }

    static func note(_ text: String, width: CGFloat) -> NSTextField {
        let n = NSTextField(wrappingLabelWithString: text)
        n.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        n.textColor = .secondaryLabelColor
        n.preferredMaxLayoutWidth = width
        return n
    }

    // MARK: Feedback

    /// A brief confirmation bubble ("Copied", "Saved to Desktop").
    static func toast(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        label.textColor = .labelColor
        let box = NSVisualEffectView()
        box.material = .hudWindow
        box.state = .active
        box.wantsLayer = true
        box.layer?.cornerRadius = 10
        box.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -8),
        ])
        return box
    }
}
