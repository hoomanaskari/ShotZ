import AppKit
import ShotzCore

/// Base for every ShotZ control: hover/press tracking, keyboard focus with ShotZ's own focus ring
/// (shown only for keyboard navigation, see `ShotzUI.FocusRing`),
/// first-mouse in non-activating panels, and drawing through the shared state → fills mapping.
/// Layer-backed; draws in `draw(_:)` with a top-left (flipped) coordinate space.
@MainActor
open class ShotzControlView: NSControl {
    public var shotzSize: ShotzUI.ControlSize = .regular { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var isSelected = false { didSet { if isSelected != oldValue { needsDisplay = true; selectionChanged() } } }
    /// Forces a visual state (previews, the gallery and tests). nil in the app.
    public var stateOverride: ShotzUI.ControlState? { didSet { needsDisplay = true } }
    /// Called when the control is activated (click, Space, Return), after `isSelected` updates.
    public var onAction: ((ShotzControlView) -> Void)?

    var isHovered = false { didSet { if isHovered != oldValue { needsDisplay = true } } }
    var isPressed = false { didSet { if isPressed != oldValue { needsDisplay = true } } }
    private var trackingArea: NSTrackingArea?
    /// Whether focus arrived by keyboard navigation (Tab); only then does the ring show.
    public private(set) var focusCameFromKeyboard = false

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        focusRingType = .none
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI controls are built in code") }

    open override var isFlipped: Bool { true }
    open override var isEnabled: Bool { didSet { needsDisplay = true } }

    /// The state used for drawing.
    public var controlState: ShotzUI.ControlState {
        if let stateOverride { return stateOverride }
        return ShotzUI.ControlState(isHovered: isHovered, isPressed: isPressed, isSelected: isSelected, isEnabled: isEnabled,
                                    isFocused: showsFocusRing)
    }

    /// The ring shows while this control has keyboard focus that came from the keyboard, in a key window.
    public var showsFocusRing: Bool {
        guard let window, window.firstResponder === self, focusCameFromKeyboard else { return false }
        return ShotzUI.FocusRing.isKeyWindow(window)
    }

    // MARK: Drawing

    open override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            drawControl(in: ctx, state: controlState)
        }
    }

    /// Subclasses draw here (colours resolve for the view's appearance).
    open func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {}

    /// The visual chrome rect: full width, `shotzSize.height` tall, centred in the (≥ 28 pt) hit frame.
    public func chromeRect(height: CGFloat? = nil) -> CGRect {
        let h = height ?? shotzSize.height
        return CGRect(x: bounds.minX, y: ((bounds.height - h) / 2).rounded(), width: bounds.width, height: h)
    }

    /// Fills, border, light-mode shadow and focus ring for a shape.
    public func drawChrome(_ path: CGPath, fills: ShotzUI.ControlFills, state: ShotzUI.ControlState, in ctx: CGContext) {
        let dark = ShotzUI.Palette.variant(effectiveAppearance).isDark
        if let bg = fills.background {
            ctx.saveGState()
            if fills.raised, !dark {
                let e = ShotzUI.Elevation.control
                ctx.setShadow(offset: CGSize(width: 0, height: -e.offsetY), blur: e.blur, color: NSColor.black.withAlphaComponent(e.opacity).cgColor)
            }
            ctx.addPath(path)
            ctx.setFillColor(bg.resolved(in: effectiveAppearance).cgColor)
            ctx.fillPath()
            ctx.restoreGState()
        }
        if let border = fills.border {
            ctx.saveGState()
            ctx.addPath(path)
            ctx.clip()
            ctx.addPath(path)
            ctx.setLineWidth(scaleAwareHairline * 2) // inner half of a centred stroke = one hairline inside
            ctx.setStrokeColor(border.resolved(in: effectiveAppearance).cgColor)
            ctx.strokePath()
            ctx.restoreGState()
        }
        if state.isFocused { drawFocusRing(path, in: ctx) }
    }

    /// ShotZ's focus ring: a 3-pt band of translucent accent just outside the shape.
    public func drawFocusRing(_ path: CGPath, in ctx: CGContext) {
        ctx.saveGState()
        // Clip to everything outside the shape, then fill a band straddling its edge.
        ctx.addRect(bounds.insetBy(dx: -8, dy: -8))
        ctx.addPath(path)
        ctx.clip(using: .evenOdd)
        ctx.addPath(path.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10))
        ctx.setFillColor(ShotzUI.Palette.focusRing.resolved(in: effectiveAppearance).cgColor)
        ctx.fillPath(using: .winding)
        ctx.restoreGState()
    }

    /// One device pixel.
    var scaleAwareHairline: CGFloat { 1 / max(window?.backingScaleFactor ?? layer?.contentsScale ?? 2, 1) }

    public func drawIcon(_ icon: ShotzIcon, in rect: CGRect, color: NSColor, ctx: CGContext) {
        icon.draw(in: ctx, rect: rect, color: color.resolved(in: effectiveAppearance).cgColor, flipped: true)
    }

    public func drawText(_ text: String, font: NSFont, color: NSColor, centeredIn rect: CGRect) {
        let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).size(withAttributes: attrs)
        let origin = CGPoint(x: rect.midX - size.width / 2, y: rect.midY - size.height / 2)
        (text as NSString).draw(at: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), withAttributes: attrs)
    }

    // MARK: Interaction

    open override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    /// Keyboard focus never comes from a pointer click (no ring after a click, and the click doesn't
    /// take the keyboard from, say, the editor canvas); Tab and Full Keyboard Access still focus it.
    open override var acceptsFirstResponder: Bool {
        isEnabled && !ShotzUI.FocusRing.isPointer(ShotzUI.FocusRing.currentEvent())
    }
    open override var canBecomeKeyView: Bool { isEnabled }
    open override var needsPanelToBecomeKey: Bool { false }
    open override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { focusCameFromKeyboard = ShotzUI.FocusRing.isKeyViewNavigation(ShotzUI.FocusRing.currentEvent()) }
        needsDisplay = true
        return accepted
    }
    open override func resignFirstResponder() -> Bool {
        let accepted = super.resignFirstResponder()
        if accepted { focusCameFromKeyboard = false }
        needsDisplay = true
        return accepted
    }

    open override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    open override func mouseEntered(with event: NSEvent) { if isEnabled { isHovered = true } }
    open override func mouseExited(with event: NSEvent) { isHovered = false }

    open override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        // A click on a keyboard-focused control hides its ring; it keeps focus.
        if focusCameFromKeyboard { focusCameFromKeyboard = false; needsDisplay = true }
        isPressed = true
        mouseDownAt(convert(event.locationInWindow, from: nil))
        // Track until mouse-up; the press shows only while the pointer is inside.
        defer { isPressed = false; trackingEnded() }
        while let window, let next = Self.nextTrackingEvent(window) {
            // The app may have replaced this control while waiting (work queued on the main queue
            // runs inside nextEvent). A view no longer in a window can't convert window points
            // (they would read as its own coordinates and land far off the track): stop here.
            guard self.window === window else { return }
            let p = convert(next.locationInWindow, from: nil)
            if next.type == .leftMouseUp {
                if bounds.contains(p) { activate(at: p) }
                return
            }
            isPressed = bounds.contains(p)
            mouseDraggedTo(p)
        }
    }

    /// The click-tracking loop's event source (drags and the mouse-up). A seam for tests, which
    /// script the mouse-up instead of running AppKit's event loop.
    public static var nextTrackingEvent: (NSWindow) -> NSEvent? = { $0.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) }

    open override func keyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == " " || event.keyCode == 36 {
            activate(at: CGPoint(x: bounds.midX, y: bounds.midY))
        } else {
            super.keyDown(with: event)
        }
    }

    /// Hooks for subclasses.
    open func mouseDownAt(_ point: CGPoint) {}
    open func mouseDraggedTo(_ point: CGPoint) {}
    open func selectionChanged() {}
    /// Called once when a press ends (mouse-up, or the control left its window mid-press).
    open func trackingEnded() {}

    /// Default activation: send the action.
    open func activate(at point: CGPoint) {
        sendAction(action, to: target)
        onAction?(self)
    }

    open override func accessibilityPerformPress() -> Bool {
        activate(at: CGPoint(x: bounds.midX, y: bounds.midY))
        return true
    }
}

extension NSView {
    /// Tooltip with an optional shortcut hint, formatted consistently: "Save  ⌘S".
    public func setShotzToolTip(_ text: String, shortcut: String? = nil) {
        toolTip = shortcut.map { "\(text)  \($0)" } ?? text
    }
}
