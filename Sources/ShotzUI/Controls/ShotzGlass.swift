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
            case .medium: 24
            case .large: 26
            }
        }
        public var glassGlyph: CGFloat {
            switch self {
            case .small: 12
            case .medium: 13
            case .large: 14
            }
        }
        /// Distance from the card edge to a corner circle.
        public var cornerInset: CGFloat { self == .small ? 6 : 8 }
        /// Size of the centred labelled pair (Copy / Save).
        public var labelSize: ControlSize { self == .large ? .regular : .compact }
        /// Small cards show icon-only centre buttons (labels don't fit two-up at 150 pt).
        public var centreShowsLabels: Bool { self != .small }
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

/// The size caption on a card ("1920 × 1080"): a small glass pill with monospaced digits.
@MainActor
public final class ShotzCaptionPill: NSView {
    public var text: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(text) } }
    public var cardSize: ShotzUI.CardSize { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    public init(_ text: String, cardSize: ShotzUI.CardSize = .large) {
        self.text = text
        self.cardSize = cardSize
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    private var font: NSFont { NSFont.monospacedDigitSystemFont(ofSize: cardSize == .small ? 10 : 11, weight: .medium) }
    private var height: CGFloat { cardSize == .small ? 18 : 20 }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: ceil((text as NSString).size(withAttributes: [.font: font]).width) + 14, height: height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let r = CGRect(x: 0, y: ((bounds.height - height) / 2).rounded(), width: bounds.width, height: height)
            let path = NSBezierPath(roundedRect: r, xRadius: height / 2, yRadius: height / 2)
            (ShotzUI.Motion.reduceTransparency ? NSColor(white: 0.1, alpha: 1) : ShotzUI.Palette.glassFill).setFill()
            path.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let s = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: (r.midX - s.width / 2).rounded(), y: (r.midY - s.height / 2).rounded()), withAttributes: attrs)
        }
    }
}

extension ShotzButton {
    /// The labelled glass pair button for a card (Copy / Save with icons; icon-only on small cards).
    public static func glass(_ title: String, icon: ShotzIcon, cardSize: ShotzUI.CardSize) -> ShotzButton {
        let b = ShotzButton(title: cardSize.centreShowsLabels ? title : nil, icon: icon, role: .glass, size: cardSize.labelSize)
        b.setAccessibilityLabel(title)
        return b
    }
}
