import AppKit

extension ShotzUI {
    /// Interaction state of a control. States combine (a selected tool can be hovered).
    public struct ControlState: Hashable, Sendable {
        public var isHovered = false
        public var isPressed = false
        public var isSelected = false
        public var isEnabled = true
        public var isFocused = false

        public init(isHovered: Bool = false, isPressed: Bool = false, isSelected: Bool = false, isEnabled: Bool = true, isFocused: Bool = false) {
            self.isHovered = isHovered
            self.isPressed = isPressed
            self.isSelected = isSelected
            self.isEnabled = isEnabled
            self.isFocused = isFocused
        }

        public static let rest = ControlState()
        public static let hover = ControlState(isHovered: true)
        public static let pressed = ControlState(isHovered: true, isPressed: true)
        public static let selected = ControlState(isSelected: true)
        public static let disabled = ControlState(isEnabled: false)
        public static let focused = ControlState(isFocused: true)

        /// The named states the gallery and tests walk through.
        public static let gallery: [(String, ControlState)] = [
            ("rest", .rest), ("hover", .hover), ("pressed", .pressed), ("selected", .selected),
            ("selected+hover", ControlState(isHovered: true, isSelected: true)), ("focused", .focused), ("disabled", .disabled),
        ]
    }

    /// What a control is for; decides its fills.
    public enum ControlRole: Sendable, CaseIterable {
        /// The one main action of a surface (Save in the editor).
        case primary
        /// Other actions with labels (Copy, Choose…).
        case secondary
        /// Low-emphasis actions: icon buttons, "more", toolbar actions. No chrome at rest.
        case quiet
        /// Tool-strip tools: quiet at rest, tinted when selected.
        case tool
        /// On/off chips (contrast outline, panel toggles).
        case chip
        /// Controls floating over images (stack hover buttons).
        case glass
        /// Destructive actions (Delete).
        case destructive
    }

    /// Resolved colours for one role in one state.
    public struct ControlFills {
        public var background: NSColor?
        public var border: NSColor?
        public var content: NSColor
        /// Raised controls cast a 1-pt soft shadow (light appearance only).
        public var raised: Bool
    }

    /// The single mapping from (role, state) to fills. Every control draws through it.
    public static func fills(for role: ControlRole, state: ControlState) -> ControlFills {
        typealias P = Palette
        var f: ControlFills
        switch role {
        case .primary:
            f = ControlFills(background: P.accentFill, border: P.accentEdge, content: P.onAccent, raised: true)
            if state.isPressed { f.background = P.accentFill.shotzDarkened(0.14) } else if state.isHovered { f.background = P.accentFill.shotzDarkened(0.07) }
        case .secondary, .destructive:
            f = ControlFills(background: P.raised, border: P.border, content: role == .destructive ? P.danger : P.textPrimary, raised: true)
            if state.isPressed { f.background = P.raised.shotzOverlay(P.fillPressed) } else if state.isHovered { f.background = P.raised.shotzOverlay(P.fillHover) }
        case .quiet:
            f = ControlFills(background: nil, border: nil, content: P.textPrimary, raised: false)
            if state.isPressed { f.background = P.fillPressed } else if state.isHovered { f.background = P.fillHover }
            if state.isSelected { f.background = P.selectedFill; f.content = P.selectedContent }
        case .tool:
            f = ControlFills(background: nil, border: nil, content: P.textPrimary, raised: false)
            if state.isSelected {
                f.background = P.selectedFill
                f.border = P.selectedBorder
                f.content = P.selectedContent
                if state.isPressed { f.background = P.selectedFill.shotzOverlay(P.fillHover) }
            } else if state.isPressed {
                f.background = P.fillPressed
            } else if state.isHovered {
                f.background = P.fillHover
            }
        case .chip:
            if state.isSelected {
                f = ControlFills(background: P.selectedFill, border: P.selectedBorder, content: P.selectedContent, raised: false)
                if state.isPressed { f.background = P.selectedFill.shotzOverlay(P.fillHover) }
            } else {
                f = ControlFills(background: nil, border: P.border, content: P.textSecondary, raised: false)
                if state.isPressed { f.background = P.fillPressed } else if state.isHovered { f.background = P.fillHover; f.content = P.textPrimary }
            }
        case .glass:
            f = ControlFills(background: state.isHovered || state.isPressed ? P.glassFillHover : P.glassFill, border: P.glassEdge,
                             content: P.glassContent, raised: false)
            if state.isPressed { f.background = P.glassFillHover.shotzDarkened(0.2) }
        }
        if !state.isEnabled {
            f.background = f.background?.withAlphaComponent((f.background?.alphaComponent ?? 1) * 0.55)
            f.border = f.border?.withAlphaComponent((f.border?.alphaComponent ?? 1) * 0.6)
            f.content = role == .primary ? P.onAccent.withAlphaComponent(0.6) : P.textTertiary
            f.raised = false
        }
        return f
    }
}

extension ShotzUI.Palette {
    /// Faint inner edge of the primary fill (definition on light backgrounds).
    static var accentEdge: NSColor { dynamic("accentEdge", black(0.10), white(0.10), black(0.35), white(0.40)) }
    /// Thin light edge of glass controls so they separate from dark image content.
    static var glassEdge: NSColor { dynamic("glassEdge", white(0.16), white(0.16), white(0.5), white(0.5)) }
}

extension NSColor {
    /// A dynamic colour darkened by `t` in every appearance.
    func shotzDarkened(_ t: CGFloat) -> NSColor {
        let base = self
        return NSColor(name: nil) { a in base.resolved(in: a).mixed(with: .black, t) }
    }

    /// `overlay` composited on top of this (dynamic) colour, keeping this colour's alpha.
    func shotzOverlay(_ overlay: NSColor) -> NSColor {
        let base = self
        return NSColor(name: nil) { a in
            let b = base.resolved(in: a), o = overlay.resolved(in: a)
            let alpha = o.alphaComponent
            return NSColor(srgbRed: b.redComponent * (1 - alpha) + o.redComponent * alpha, green: b.greenComponent * (1 - alpha) + o.greenComponent * alpha,
                           blue: b.blueComponent * (1 - alpha) + o.blueComponent * alpha, alpha: max(b.alphaComponent, alpha))
        }
    }
}
