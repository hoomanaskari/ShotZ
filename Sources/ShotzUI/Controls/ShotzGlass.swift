import AppKit
import ShotzCore

extension ShotzUI {
    /// Quick-access card sizes (SPEC §4.2) and the glass metrics that go with each.
    public enum CardSize: String, Sendable, CaseIterable {
        case small, medium, large

        public var width: CGFloat {
            switch self {
            case .small: 150
            case .medium: 200
            case .large: 250
            }
        }
        /// Cards are 16:10.
        public var height: CGFloat { (width / 1.6).rounded() }
        /// Corner glass circles.
        public var glassDiameter: CGFloat {
            switch self {
            case .small: 22
            case .medium: 28
            case .large: 30
            }
        }
        public var glassGlyph: CGFloat {
            switch self {
            case .small: 12
            case .medium: 15
            case .large: 16
            }
        }
        /// Distance from the card edge to a corner circle.
        public var cornerInset: CGFloat { self == .small ? 6 : 8 }
        /// Size of the centred labelled pair (Copy / Save).
        public var labelSize: ControlSize { self == .large ? .regular : .compact }
        /// Small cards use a tighter labelled pair (11-pt label, 6-pt padding) so two fit in 150 pt.
        var isTight: Bool { self == .small }
        public var cornerRadius: CGFloat { self == .small ? 8 : 10 }
    }
}

/// A circular glass icon button for use over images (stack card corners).
/// The circle is `diameter` wide; the hit target never drops below 28 pt.
@MainActor
public final class ShotzGlassIconButton: ShotzControlView {
    public var icon: ShotzIcon { didSet { needsDisplay = true; setAccessibilityLabel(icon.accessibilityDescription) } }
    public var diameter: CGFloat { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    public var glyphSize: CGFloat { didSet { needsDisplay = true } }

    public init(icon: ShotzIcon, cardSize: ShotzUI.CardSize = .large) {
        self.icon = icon
        diameter = cardSize.glassDiameter
        glyphSize = cardSize.glassGlyph
        super.init(frame: .zero)
        setAccessibilityRole(.button)
        setAccessibilityLabel(icon.accessibilityDescription)
    }

    public override var intrinsicContentSize: NSSize {
        let side = max(diameter, 28)
        return NSSize(width: side, height: side)
    }

    public override func drawControl(in ctx: CGContext, state: ShotzUI.ControlState) {
        let r = CGRect(x: ((bounds.width - diameter) / 2).rounded(), y: ((bounds.height - diameter) / 2).rounded(), width: diameter, height: diameter)
        let path = CGPath(ellipseIn: r, transform: nil)
        let fills = ShotzUI.fills(for: .glass, state: state)
        if ShotzUI.Motion.reduceTransparency {
            var solid = fills
            solid.background = NSColor(white: 0.1, alpha: state.isEnabled ? 1 : 0.6)
            drawChrome(path, fills: solid, state: state, in: ctx)
        } else {
            drawChrome(path, fills: fills, state: state, in: ctx)
        }
        drawIcon(icon, in: CGRect(x: (r.midX - glyphSize / 2).rounded(), y: (r.midY - glyphSize / 2).rounded(), width: glyphSize, height: glyphSize),
                 color: fills.content, ctx: ctx)
    }
}

/// A non-interactive glass label over images: the size caption on a card, a hint, a value.
/// Static text for VoiceOver; it never takes the mouse (no tracking, `hitTest` returns nil).
@MainActor
public class ShotzGlassLabel: NSView {
    public var text: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(text) } }
    /// `.caption` for words, `.value` for numbers (monospaced digits).
    public var style: ShotzUI.Typography { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }
    /// Pill height (18 on small cards, 20 elsewhere).
    public var pillHeight: CGFloat { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    public init(_ text: String, style: ShotzUI.Typography = .caption, height: CGFloat = 20) {
        self.text = text
        self.style = style
        self.pillHeight = height
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    public override func hitTest(_ point: NSPoint) -> NSView? { nil }
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { false }

    var font: NSFont {
        let size = pillHeight < 20 ? style.size - 1 : style.size - (style == .caption ? 0 : 1)
        return style == .value ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: .medium) : NSFont.systemFont(ofSize: size, weight: .medium)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: [.font: font]).width) + 14, height: pillHeight)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let h = pillHeight
            let r = CGRect(x: 0, y: ((bounds.height - h) / 2).rounded(), width: bounds.width, height: h)
            let path = NSBezierPath(roundedRect: r, xRadius: h / 2, yRadius: h / 2)
            (ShotzUI.Motion.reduceTransparency ? NSColor(white: 0.1, alpha: 1) : ShotzUI.Palette.glassFill).setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let s = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (r.midX - s.width / 2).rounded(), y: (r.midY - s.height / 2).rounded()), withAttributes: attrs)
        }
    }
}

/// The size caption on a card ("1920 × 1080"): a glass label with monospaced digits sized for the card.
@MainActor
public final class ShotzCaptionPill: ShotzGlassLabel {
    public var cardSize: ShotzUI.CardSize { didSet { pillHeight = cardSize == .small ? 18 : 20 } }

    public init(_ text: String, cardSize: ShotzUI.CardSize = .large) {
        self.cardSize = cardSize
        super.init(text, style: .value, height: cardSize == .small ? 18 : 20)
    }
}

extension ShotzButton {
    /// The glass pair button for a card (Copy / Save): icon + label at every card size, or icon-only
    /// when `iconOnly` (the title becomes the accessibility label and tooltip).
    public static func glass(_ title: String, icon: ShotzIcon, cardSize: ShotzUI.CardSize, iconOnly: Bool = false) -> ShotzButton {
        if iconOnly {
            let b = ShotzButton(icon: icon, role: .glass, size: cardSize.labelSize)
            b.setAccessibilityLabel(title)
            b.setShotzToolTip(title)
            return b
        }
        let b = ShotzButton(title: title, icon: icon, role: .glass, size: cardSize.labelSize)
        if cardSize.isTight {
            b.titleFont = NSFont.systemFont(ofSize: 11, weight: .medium)
            b.paddingOverride = 6
            b.iconSizeOverride = 12
        }
        return b
    }
}
