import AppKit

/// The custom colour: a rainbow ring around the current colour. Clicking opens the
/// system colour panel; changes preview live and settle into one undo step.
@MainActor final class CustomColorWell: NSControl {
    var color: NSColor { didSet { needsDisplay = true } }
    /// True when the current colour is not one of the presets (the ring shows it filled).
    var isCustom: Bool { didSet { needsDisplay = true } }
    /// `(colour, isFinal)`.
    var onChange: ((NSColor, Bool) -> Void)?
    private var settle: DispatchWorkItem?

    init(color: NSColor, isCustom: Bool, label: String) {
        self.color = color
        self.isCustom = isCustom
        super.init(frame: NSRect(x: 0, y: 0, width: 24, height: 24))
        toolTip = label
        setAccessibilityElement(true)
        setAccessibilityRole(.colorWell)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 24).isActive = true
        heightAnchor.constraint(equalToConstant: 24).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        let r = bounds.insetBy(dx: 2, dy: 2)
        let c = NSPoint(x: r.midX, y: r.midY)
        // Hue wheel ring.
        let steps = 36
        for i in 0..<steps {
            let a0 = CGFloat(i) / CGFloat(steps) * 360, a1 = CGFloat(i + 1) / CGFloat(steps) * 360 + 0.8
            let p = NSBezierPath()
            p.move(to: c)
            p.appendArc(withCenter: c, radius: r.width / 2, startAngle: a0, endAngle: a1)
            p.close()
            NSColor(calibratedHue: CGFloat(i) / CGFloat(steps), saturation: 0.85, brightness: 0.95, alpha: 1).setFill()
            p.fill()
        }
        // Centre: the custom colour, or a neutral dot with a plus.
        let inner = r.insetBy(dx: 4, dy: 4)
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(ovalIn: inner.insetBy(dx: -1.5, dy: -1.5)).fill()
        if isCustom {
            color.setFill()
            NSBezierPath(ovalIn: inner).fill()
        } else {
            NSColor.secondaryLabelColor.setStroke()
            let plus = NSBezierPath()
            plus.lineWidth = 1.4
            plus.lineCapStyle = .round
            plus.move(to: NSPoint(x: c.x - 3, y: c.y)); plus.line(to: NSPoint(x: c.x + 3, y: c.y))
            plus.move(to: NSPoint(x: c.x, y: c.y - 3)); plus.line(to: NSPoint(x: c.x, y: c.y + 3))
            plus.stroke()
        }
        if isCustom {
            NSColor.controlAccentColor.setStroke()
            let ring = NSBezierPath(ovalIn: bounds.insetBy(dx: 0.75, dy: 0.75))
            ring.lineWidth = 1.5
            ring.stroke()
        }
    }

    override func mouseDown(with event: NSEvent) { openPanel() }
    override func accessibilityPerformPress() -> Bool { openPanel(); return true }

    func openPanel() {
        let panel = NSColorPanel.shared
        panel.showsAlpha = false
        panel.color = color
        panel.setTarget(self)
        panel.setAction(#selector(panelChanged(_:)))
        panel.isContinuous = true
        panel.orderFront(nil)
    }

    @objc private func panelChanged(_ panel: NSColorPanel) {
        color = panel.color
        isCustom = true
        onChange?(panel.color, false)
        // Many live changes, one undo step: settle shortly after the last one.
        settle?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.onChange?(self.color, true)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }
}

/// Samples a colour from anywhere on screen (the system colour sampler).
@MainActor final class EyedropperButton: NSButton {
    var onPick: ((NSColor) -> Void)?

    init(label: String) {
        super.init(frame: NSRect(x: 0, y: 0, width: 26, height: EditorMetrics.optionHeight))
        image = EditorGlyphs.image(.eyedropper, size: 16, label: label)
        imagePosition = .imageOnly
        isBordered = false
        bezelStyle = .accessoryBarAction
        contentTintColor = .secondaryLabelColor
        toolTip = label
        setAccessibilityLabel(label)
        target = self
        action = #selector(pick)
        translatesAutoresizingMaskIntoConstraints = false
        widthAnchor.constraint(equalToConstant: 26).isActive = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    @objc private func pick() {
        NSColorSampler().show { [weak self] color in
            guard let color else { return }
            MainActor.assumeIsolated { self?.onPick?(color) }
        }
    }
}

/// A slider with a leading glyph and a trailing value readout, on the 8-pt rhythm.
@MainActor final class ValueSliderRow: NSStackView {
    let slider: NSSlider
    private let valueLabel = NSTextField(labelWithString: "")
    private let format: (Double) -> String

    init(glyph: EditorGlyph?, label: String, slider: NSSlider, width: CGFloat, format: @escaping (Double) -> String) {
        self.slider = slider
        self.format = format
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = 6
        alignment = .centerY
        if let glyph {
            let icon = NSImageView(image: EditorGlyphs.image(glyph, size: 16, label: label))
            icon.contentTintColor = .secondaryLabelColor
            icon.toolTip = label
            addArrangedSubview(icon)
        }
        slider.widthAnchor.constraint(equalToConstant: width).isActive = true
        addArrangedSubview(slider)
        valueLabel.font = .monospacedDigitSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
        valueLabel.textColor = .secondaryLabelColor
        valueLabel.alignment = .right
        valueLabel.widthAnchor.constraint(equalToConstant: 34).isActive = true
        addArrangedSubview(valueLabel)
        refresh()
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func refresh() {
        valueLabel.stringValue = format(slider.doubleValue)
        slider.setAccessibilityValueDescription(valueLabel.stringValue)
    }
}
