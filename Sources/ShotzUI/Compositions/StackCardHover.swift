import AppKit
import ShotzCore

/// Reference composition for a quick-access card on hover, built from glass controls:
/// close (top-left), annotate (top-right), Copy and Save centred, Quick Look (bottom-right) and the
/// size caption (bottom-left). Corner buttons are 24-pt glass circles inset 8 pt; the centre pair are
/// regular glass capsules with 8 pt between. The image dims by 25 % under the controls.
@MainActor
public final class StackCardHover: NSView {
    public let closeButton = ShotzButton(icon: .close, role: .glass, size: .compact)
    public let annotateButton = ShotzButton(icon: .annotate, role: .glass, size: .compact)
    public let quickLookButton = ShotzButton(icon: .quickLook, role: .glass, size: .compact)
    public let copyButton = ShotzButton(title: String(localized: "Copy"), role: .glass)
    public let saveButton = ShotzButton(title: String(localized: "Save"), role: .glass)
    public var caption = "1920 × 1080" { didSet { needsDisplay = true } }
    /// Draws the card's image (the stack supplies the thumbnail).
    public var drawImage: ((CGContext, CGRect) -> Void)?

    public override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        closeButton.setShotzToolTip(String(localized: "Close"), shortcut: "⌘W")
        annotateButton.setShotzToolTip(String(localized: "Annotate"), shortcut: "⌘E")
        quickLookButton.setShotzToolTip(String(localized: "Quick Look"), shortcut: "Space")
        copyButton.setShotzToolTip(String(localized: "Copy"), shortcut: "⌘C")
        saveButton.setShotzToolTip(String(localized: "Save"), shortcut: "⌘S")
        let pair = max(copyButton.intrinsicContentSize.width, saveButton.intrinsicContentSize.width)
        copyButton.minimumWidth = pair
        saveButton.minimumWidth = pair
        for b in [closeButton, annotateButton, quickLookButton, copyButton, saveButton] { addSubview(b) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    public static let cornerRadius: CGFloat = 10

    public override func layout() {
        super.layout()
        let inset: CGFloat = 6 // 28-pt hit areas → 24-pt glass circles land 8 pt from the edge
        let s = closeButton.intrinsicContentSize
        closeButton.frame = CGRect(x: inset, y: inset, width: s.width, height: s.height)
        annotateButton.frame = CGRect(x: bounds.maxX - inset - s.width, y: inset, width: s.width, height: s.height)
        quickLookButton.frame = CGRect(x: bounds.maxX - inset - s.width, y: bounds.maxY - inset - s.height, width: s.width, height: s.height)
        let c = copyButton.intrinsicContentSize
        let total = 2 * c.width + ShotzUI.Space.s
        copyButton.frame = CGRect(x: (bounds.midX - total / 2).rounded(), y: (bounds.midY - c.height / 2).rounded(), width: c.width, height: c.height)
        saveButton.frame = copyButton.frame.offsetBy(dx: c.width + ShotzUI.Space.s, dy: 0)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
            ctx.saveGState()
            card.addClip()
            ShotzUI.Palette.surfaceSunken.composited(over: ShotzUI.Palette.surface.resolved(in: effectiveAppearance)).setFill()
            bounds.fill()
            drawImage?(ctx, bounds)
            NSColor.black.withAlphaComponent(0.25).setFill()
            bounds.fill()
            ctx.restoreGState()
            ShotzUI.Palette.border.setStroke()
            card.lineWidth = 1
            card.stroke()
            // Caption on a small glass pill, bottom-left, aligned with the corner buttons.
            let attrs: [NSAttributedString.Key: Any] = [.font: ShotzUI.Typography.caption.font.withMonospacedDigits, .foregroundColor: NSColor.white]
            let size = (caption as NSString).size(withAttributes: attrs)
            let pill = CGRect(x: 8, y: bounds.maxY - 8 - 20, width: ceil(size.width) + 14, height: 20)
            let pillPath = NSBezierPath(roundedRect: pill, xRadius: 10, yRadius: 10)
            ShotzUI.Palette.glassFill.setFill()
            pillPath.fill()
            (caption as NSString).draw(at: CGPoint(x: pill.minX + 7, y: (pill.midY - size.height / 2).rounded()), withAttributes: attrs)
        }
    }
}

extension NSFont {
    var withMonospacedDigits: NSFont {
        NSFont.monospacedDigitSystemFont(ofSize: pointSize, weight: .regular)
    }
}
