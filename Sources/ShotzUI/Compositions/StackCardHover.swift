import AppKit
import ShotzCore

/// Reference composition for a quick-access card on hover, built from the glass controls:
/// close (top-left), annotate (top-right), the Copy / Save pair centred, Quick Look
/// (bottom-right) and the size caption pill (bottom-left). Metrics come from `ShotzUI.CardSize`:
/// corner circles 22 / 28 / 30 pt (hit ≥ 28) inset 6 / 8 / 8 pt; the centre pair is icon + label at
/// every size: tight compact on small, compact on medium, regular on large, 8 pt apart (6 on small).
/// The image dims by 25 %.
@MainActor
public final class StackCardHover: NSView {
    public let cardSize: ShotzUI.CardSize
    public let closeButton: ShotzGlassIconButton
    public let annotateButton: ShotzGlassIconButton
    public let quickLookButton: ShotzGlassIconButton
    public let copyButton: ShotzButton
    public let saveButton: ShotzButton
    public let caption: ShotzCaptionPill
    /// Draws the card's image (the stack supplies the thumbnail).
    public var drawImage: ((CGContext, CGRect) -> Void)?

    public init(cardSize: ShotzUI.CardSize = .large, caption text: String = "1920 × 1080") {
        self.cardSize = cardSize
        closeButton = ShotzGlassIconButton(icon: .close, cardSize: cardSize)
        annotateButton = ShotzGlassIconButton(icon: .annotate, cardSize: cardSize)
        quickLookButton = ShotzGlassIconButton(icon: .quickLook, cardSize: cardSize)
        copyButton = .glass(String(localized: "Copy"), icon: .copy, cardSize: cardSize)
        saveButton = .glass(String(localized: "Save"), icon: .save, cardSize: cardSize)
        caption = ShotzCaptionPill(text, cardSize: cardSize)
        super.init(frame: CGRect(x: 0, y: 0, width: cardSize.width, height: cardSize.height))
        wantsLayer = true
        closeButton.setShotzToolTip(String(localized: "Close"), shortcut: "⌘W")
        annotateButton.setShotzToolTip(String(localized: "Annotate"), shortcut: "⌘E")
        quickLookButton.setShotzToolTip(String(localized: "Quick Look"), shortcut: "Space")
        copyButton.setShotzToolTip(String(localized: "Copy"), shortcut: "⌘C")
        saveButton.setShotzToolTip(String(localized: "Save"), shortcut: "⌘S")
        let pair = max(copyButton.intrinsicContentSize.width, saveButton.intrinsicContentSize.width)
        copyButton.minimumWidth = pair
        saveButton.minimumWidth = pair
        for v in [closeButton, annotateButton, quickLookButton, copyButton, saveButton, caption] as [NSView] { addSubview(v) }
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }

    public override func layout() {
        super.layout()
        let s = closeButton.intrinsicContentSize
        // Hit areas are ≥ 28 pt; offset so the visible circle sits `cornerInset` from the edge.
        let o = cardSize.cornerInset - (s.width - cardSize.glassDiameter) / 2
        closeButton.frame = CGRect(x: o, y: o, width: s.width, height: s.height)
        annotateButton.frame = CGRect(x: bounds.maxX - o - s.width, y: o, width: s.width, height: s.height)
        quickLookButton.frame = CGRect(x: bounds.maxX - o - s.width, y: bounds.maxY - o - s.height, width: s.width, height: s.height)
        let c = copyButton.intrinsicContentSize
        let gap = cardSize == .small ? 6 : ShotzUI.Space.s
        let total = 2 * c.width + gap
        copyButton.frame = CGRect(x: (bounds.midX - total / 2).rounded(), y: (bounds.midY - c.height / 2).rounded(), width: c.width, height: c.height)
        saveButton.frame = copyButton.frame.offsetBy(dx: c.width + gap, dy: 0)
        let p = caption.intrinsicContentSize
        caption.frame = CGRect(x: cardSize.cornerInset, y: (quickLookButton.frame.midY - p.height / 2).rounded(), width: p.width, height: p.height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let r = cardSize.cornerRadius
            let card = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.5, dy: 0.5), xRadius: r, yRadius: r)
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
        }
    }
}
