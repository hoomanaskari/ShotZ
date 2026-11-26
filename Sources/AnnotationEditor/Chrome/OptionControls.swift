import AppKit

/// Closure-backed target/action for AppKit controls.
@MainActor final class ControlAction: NSObject {
    let handler: (NSControl) -> Void
    init(_ handler: @escaping (NSControl) -> Void) { self.handler = handler }
    @objc func fire(_ sender: NSControl) { handler(sender) }
}

/// Builders for the small, consistent controls of the options bar and background panel.
@MainActor final class OptionControls {
    private(set) var actions: [ControlAction] = []

    func reset() { actions.removeAll() }

    private func bind(_ control: NSControl, _ handler: @escaping (NSControl) -> Void) {
        let a = ControlAction(handler)
        actions.append(a)
        control.target = a
        control.action = #selector(ControlAction.fire(_:))
    }

    func segmented(
        images: [NSImage], labels: [String], selected: Int?, _ handler: @escaping (Int) -> Void
    ) -> NSSegmentedControl {
        let c = NSSegmentedControl(images: images, trackingMode: .selectOne, target: nil, action: nil)
        c.controlSize = .small
        c.segmentStyle = .rounded
        for (i, label) in labels.enumerated() where i < c.segmentCount {
            c.setToolTip(label, forSegment: i)
            c.setLabel("", forSegment: i)
        }
        if let selected { c.selectedSegment = selected }
        c.setAccessibilityLabel(labels.joined(separator: ", "))
        bind(c) { handler(($0 as? NSSegmentedControl)?.selectedSegment ?? 0) }
        return c
    }

    func segmented(titles: [String], selected: Int?, _ handler: @escaping (Int) -> Void) -> NSSegmentedControl {
        let c = NSSegmentedControl(labels: titles, trackingMode: .selectOne, target: nil, action: nil)
        c.controlSize = .small
        if let selected { c.selectedSegment = selected }
        bind(c) { handler(($0 as? NSSegmentedControl)?.selectedSegment ?? 0) }
        return c
    }

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

    func toggle(symbol: String, label: String, on: Bool, _ handler: @escaping (Bool) -> Void) -> NSButton {
        let b = NSButton(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage(), target: nil, action: nil)
        b.setButtonType(.pushOnPushOff)
        b.bezelStyle = .toolbar
        b.controlSize = .small
        b.state = on ? .on : .off
        b.toolTip = label
        b.setAccessibilityLabel(label)
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

    func button(_ title: String, _ handler: @escaping () -> Void) -> NSButton {
        let b = NSButton(title: title, target: nil, action: nil)
        b.controlSize = .small
        b.bezelStyle = .push
        bind(b) { _ in handler() }
        return b
    }

    func popup(_ titles: [String], selected: Int, label: String, _ handler: @escaping (Int) -> Void) -> NSPopUpButton {
        let p = NSPopUpButton(frame: .zero, pullsDown: false)
        p.controlSize = .small
        p.font = .systemFont(ofSize: NSFont.smallSystemFontSize)
        p.addItems(withTitles: titles)
        p.selectItem(at: selected)
        p.setAccessibilityLabel(label)
        p.toolTip = label
        bind(p) { handler(($0 as? NSPopUpButton)?.indexOfSelectedItem ?? 0) }
        return p
    }

    func numberField(_ value: Int, width: CGFloat = 54, label: String, _ handler: @escaping (Int) -> Void) -> NSTextField {
        let f = NSTextField(string: String(value))
        f.controlSize = .small
        f.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        f.alignment = .right
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        let formatter = NumberFormatter()
        formatter.allowsFloats = false
        formatter.minimum = 1
        f.formatter = formatter
        f.setAccessibilityLabel(label)
        f.toolTip = label
        bind(f) { handler(Int(($0 as? NSTextField)?.stringValue ?? "") ?? value) }
        return f
    }

    func colorWell(_ color: NSColor, label: String, _ handler: @escaping (NSColor, Bool) -> Void) -> NSColorWell {
        let w = NSColorWell(style: .minimal)
        w.color = color
        w.widthAnchor.constraint(equalToConstant: 26).isActive = true
        w.heightAnchor.constraint(equalToConstant: 18).isActive = true
        w.supportsAlpha = false
        w.setAccessibilityLabel(label)
        w.toolTip = label
        bind(w) { control in
            guard let well = control as? NSColorWell else { return }
            handler(well.color, NSApp.currentEvent?.type != .leftMouseDragged)
        }
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

    /// A small secondary-coloured symbol labelling the control after it.
    static func icon(_ symbol: String, label: String) -> NSImageView {
        let v = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: label) ?? NSImage())
        v.contentTintColor = .secondaryLabelColor
        v.symbolConfiguration = .init(pointSize: 12, weight: .regular)
        v.toolTip = label
        return v
    }

    static func separator() -> NSView {
        let v = NSBox()
        v.boxType = .separator
        v.heightAnchor.constraint(equalToConstant: 16).isActive = true
        v.widthAnchor.constraint(equalToConstant: 1).isActive = true
        return v
    }
}
