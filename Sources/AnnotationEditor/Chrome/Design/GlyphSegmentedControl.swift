import AppKit

/// Shared spacing and sizes: an 8-pt rhythm throughout the chrome.
enum EditorMetrics {
    static let unit: CGFloat = 8
    static let toolHeight: CGFloat = 32
    static let optionHeight: CGFloat = 26
    static let barHeight: CGFloat = 42
    static let corner: CGFloat = 7

    private static func dark(_ a: NSAppearance) -> Bool { a.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua }
    /// Explicit light/dark tones (not vibrant label colours, which read heavy inside a sidebar).
    static let track = NSColor(name: nil) { dark($0) ? NSColor(white: 1, alpha: 0.07) : NSColor(white: 0, alpha: 0.055) }
    static let chip = NSColor(name: nil) { dark($0) ? NSColor(white: 1, alpha: 0.2) : .white }
    static let hover = NSColor(name: nil) { dark($0) ? NSColor(white: 1, alpha: 0.08) : NSColor(white: 0, alpha: 0.06) }
    static let press = NSColor(name: nil) { dark($0) ? NSColor(white: 1, alpha: 0.14) : NSColor(white: 0, alpha: 0.11) }
}

/// A row of glyph (or text) segments with one selection. `.tools` draws a strong
/// accent-filled selection (the tool strip); `.options` a raised chip inside a tinted
/// track (style pickers). Segments can be split into groups. Each segment is a
/// VoiceOver radio button with its own label; arrow keys move the selection when focused.
@MainActor final class GlyphSegmentedControl: NSControl {
    enum Style { case tools, options }

    struct Segment {
        var image: NSImage?
        var title: String?
        /// VoiceOver label and tooltip.
        var label: String
        /// Shown in the tooltip after the label, e.g. "A".
        var shortcut: String?
    }

    let style: Style
    private(set) var segments: [Segment]
    /// Indices that start a new group (a gap and a divider before them).
    var groupStarts: Set<Int> = []
    var selectedIndex: Int? { didSet { needsDisplay = true; updateAccessibility() } }
    var onSelect: ((Int) -> Void)?
    private var hovered: Int?
    private var pressed: Int?
    private var tracking: NSTrackingArea?
    private var elements: [SegmentElement] = []

    init(style: Style, segments: [Segment], selected: Int?, label: String) {
        self.style = style
        self.segments = segments
        selectedIndex = selected
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.radioGroup)
        setAccessibilityLabel(label)
        translatesAutoresizingMaskIntoConstraints = false
        rebuildAccessibility()
        updateToolTips()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var isFlipped: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Drawn with explicit tones; vibrancy in the sidebar would darken the track.
    override var allowsVibrancy: Bool { false }

    private var segmentWidth: CGFloat {
        switch style {
        case .tools: 36
        case .options: segments.contains { $0.title != nil } ? 0 : 30
        }
    }
    private var height: CGFloat { style == .tools ? EditorMetrics.toolHeight : EditorMetrics.optionHeight }
    private let groupGap: CGFloat = 9

    private func width(of i: Int) -> CGFloat {
        if segmentWidth > 0 { return segmentWidth }
        let title = segments[i].title ?? ""
        let w = (title as NSString).size(withAttributes: [.font: titleFont]).width
        return max(26, ceil(w) + 12)
    }

    private var titleFont: NSFont { .systemFont(ofSize: NSFont.smallSystemFontSize, weight: .medium) }

    /// Segment frames in view coordinates.
    func frames() -> [NSRect] {
        var x: CGFloat = 2
        var out: [NSRect] = []
        for i in segments.indices {
            if groupStarts.contains(i) { x += groupGap }
            let w = width(of: i)
            out.append(NSRect(x: x, y: 2, width: w, height: height - 4))
            x += w
        }
        return out
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: (frames().last?.maxX ?? 0) + 2, height: height)
    }

    // MARK: Drawing

    override func draw(_ dirtyRect: NSRect) {
        let frames = frames()
        let accent = NSColor.controlAccentColor
        if style == .options {
            // Tinted track behind the segments.
            EditorMetrics.track.setFill()
            NSBezierPath(roundedRect: bounds, xRadius: EditorMetrics.corner, yRadius: EditorMetrics.corner).fill()
        }
        for (i, f) in frames.enumerated() {
            if groupStarts.contains(i), style == .tools {
                NSColor.separatorColor.setFill()
                NSRect(x: f.minX - groupGap / 2 - 0.5, y: f.minY + 7, width: 1, height: f.height - 14).fill()
            }
            let selected = i == selectedIndex
            let chip = f.insetBy(dx: style == .tools ? 1 : 1.5, dy: style == .tools ? 0 : 1)
            let path = NSBezierPath(roundedRect: chip, xRadius: EditorMetrics.corner - 1.5, yRadius: EditorMetrics.corner - 1.5)
            var glyphColor = NSColor.secondaryLabelColor
            switch (style, selected) {
            case (.tools, true):
                accent.setFill()
                path.fill()
                glyphColor = .white
            case (.options, true):
                EditorMetrics.chip.setFill()
                let shadow = NSShadow()
                shadow.shadowColor = NSColor.black.withAlphaComponent(0.16)
                shadow.shadowBlurRadius = 2
                shadow.shadowOffset = NSSize(width: 0, height: -0.5)
                NSGraphicsContext.saveGraphicsState()
                shadow.set()
                path.fill()
                NSGraphicsContext.restoreGraphicsState()
                glyphColor = .labelColor
            default:
                if i == pressed || i == hovered {
                    (i == pressed ? EditorMetrics.press : EditorMetrics.hover).setFill()
                    path.fill()
                }
                glyphColor = style == .tools ? .labelColor.withAlphaComponent(0.82) : .secondaryLabelColor
            }
            if let image = segments[i].image {
                let size: CGFloat = style == .tools ? 20 : 18
                let r = NSRect(x: f.midX - size / 2, y: f.midY - size / 2, width: size, height: size)
                tinted(image, glyphColor).draw(in: r)
            } else if let title = segments[i].title {
                let attrs: [NSAttributedString.Key: Any] = [.font: titleFont, .foregroundColor: glyphColor]
                let s = (title as NSString).size(withAttributes: attrs)
                (title as NSString).draw(at: NSPoint(x: f.midX - s.width / 2, y: f.midY - s.height / 2), withAttributes: attrs)
            }
        }
    }

    private func tinted(_ image: NSImage, _ color: NSColor) -> NSImage {
        NSImage(size: image.size, flipped: false) { r in
            image.draw(in: r)
            color.set()
            r.fill(using: .sourceAtop)
            return true
        }
    }

    // MARK: Mouse

    private func index(at p: NSPoint) -> Int? { frames().firstIndex { $0.contains(p) } }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let tracking { removeTrackingArea(tracking) }
        let t = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect],
                               owner: self, userInfo: nil)
        addTrackingArea(t)
        tracking = t
    }

    override func mouseMoved(with event: NSEvent) {
        let i = index(at: convert(event.locationInWindow, from: nil))
        if i != hovered { hovered = i; needsDisplay = true }
    }

    override func mouseExited(with event: NSEvent) { hovered = nil; needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        pressed = index(at: convert(event.locationInWindow, from: nil))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        defer { pressed = nil; needsDisplay = true }
        guard let i = index(at: convert(event.locationInWindow, from: nil)), i == pressed else { return }
        choose(i)
    }

    func choose(_ i: Int) {
        guard segments.indices.contains(i) else { return }
        selectedIndex = i
        onSelect?(i)
    }

    // MARK: Keyboard (Full Keyboard Access)

    override var acceptsFirstResponder: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var canBecomeKeyView: Bool { NSApp.isFullKeyboardAccessEnabled }
    override var focusRingMaskBounds: NSRect { bounds }
    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: EditorMetrics.corner, yRadius: EditorMetrics.corner).fill()
    }

    override func keyDown(with event: NSEvent) {
        let current = selectedIndex ?? 0
        switch event.keyCode {
        case 123: choose(max(current - 1, 0))
        case 124: choose(min(current + 1, segments.count - 1))
        default: super.keyDown(with: event)
        }
    }

    // MARK: Tooltips and accessibility

    private func updateToolTips() {
        removeAllToolTips()
        for (i, f) in frames().enumerated() {
            let s = segments[i]
            addToolTip(f, owner: s.shortcut.map { "\(s.label)  \($0)" } ?? s.label as NSString, userData: nil)
        }
    }

    override func layout() {
        super.layout()
        updateToolTips()
        for (e, f) in zip(elements, frames()) { e.setAccessibilityFrameInParentSpace(f) }
    }

    private func rebuildAccessibility() {
        elements = segments.enumerated().map { i, s in
            let e = SegmentElement()
            e.setAccessibilityParent(self)
            e.setAccessibilityRole(.radioButton)
            e.setAccessibilityLabel(s.label)
            e.setAccessibilityHelp(s.shortcut.map { String(localized: "Shortcut \($0)") })
            e.press = { [weak self] in self?.choose(i) }
            return e
        }
        setAccessibilityChildren(elements)
        updateAccessibility()
    }

    private func updateAccessibility() {
        for (i, e) in elements.enumerated() { e.setAccessibilityValue(i == selectedIndex ? 1 : 0) }
    }
}

/// One segment, for VoiceOver.
final class SegmentElement: NSAccessibilityElement {
    // Set once on the main actor when the element is built; VoiceOver calls
    // accessibilityPerformPress on the main thread.
    nonisolated(unsafe) var press: (@MainActor @Sendable () -> Void)?
    override func accessibilityPerformPress() -> Bool {
        guard let press else { return false }
        MainActor.assumeIsolated { press() }
        return true
    }
}
