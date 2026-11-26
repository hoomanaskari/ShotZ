import AppKit
import ShotzCore

/// A confirmation pill ("Copied", "Saved", "Couldn't save"): glass capsule with a status glyph.
/// Use `show(in:)` to fade it in over a view and dismiss it automatically.
@MainActor
public final class ShotzToast: NSView {
    public enum Tone: Sendable { case success, failure, info }
    public var text: String { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(text) } }
    public var tone: Tone { didSet { needsDisplay = true } }

    /// Compact toasts (24 pt) fit on quick-access cards; regular (32 pt) suits windows.
    public var compact = false { didSet { invalidateIntrinsicContentSize(); needsDisplay = true } }

    public init(_ text: String, tone: Tone = .success, compact: Bool = false) {
        self.text = text
        self.tone = tone
        self.compact = compact
        super.init(frame: .zero)
        wantsLayer = true
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(text)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    private var height: CGFloat { compact ? 24 : 32 }
    private var glyph: CGFloat { compact ? 13 : 16 }
    private var textFont: NSFont { compact ? ShotzUI.Typography.label.font : ShotzUI.Typography.control.font }
    private var lead: CGFloat { compact ? ShotzUI.Space.s + 2 : ShotzUI.Space.m }
    private var icon: ShotzIcon { tone == .success ? .success : tone == .failure ? .failure : .info }

    public override var intrinsicContentSize: NSSize {
        let w = lead + glyph + ShotzUI.Space.xs + 2 + ceil((text as NSString).size(withAttributes: [.font: textFont]).width) + lead + 2
        return NSSize(width: ceil(w), height: height)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            guard let ctx = NSGraphicsContext.current?.cgContext else { return }
            let r = CGRect(x: 0, y: (bounds.height - height) / 2, width: bounds.width, height: height)
            let path = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: height / 2, yRadius: height / 2)
            (ShotzUI.Motion.reduceTransparency ? NSColor(white: 0.1, alpha: 1) : ShotzUI.Palette.glassFill).setFill()
            path.fill()
            ShotzUI.Palette.glassEdge.setStroke()
            path.lineWidth = 1
            path.stroke()
            let glyphColor: NSColor = tone == .success ? NSColor(srgbRed: 0.45, green: 0.88, blue: 0.62, alpha: 1)
                : tone == .failure ? NSColor(srgbRed: 1, green: 0.62, blue: 0.58, alpha: 1) : .white
            icon.draw(in: ctx, rect: CGRect(x: lead, y: (r.midY - glyph / 2).rounded(), width: glyph, height: glyph), color: glyphColor.cgColor, flipped: true)
            let attrs: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.white]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: lead + glyph + ShotzUI.Space.xs + 2, y: (r.midY - size.height / 2).rounded()), withAttributes: attrs)
        }
    }

    /// Shows the toast centred near the bottom of `view`, then removes it after `duration`.
    public func show(in view: NSView, duration: TimeInterval = 1.4) {
        let size = intrinsicContentSize
        frame = CGRect(x: ((view.bounds.width - size.width) / 2).rounded(), y: view.isFlipped ? view.bounds.height - size.height - ShotzUI.Space.l : ShotzUI.Space.l,
                       width: size.width, height: size.height)
        alphaValue = 0
        view.addSubview(self)
        NSAccessibility.post(element: self, notification: .announcementRequested, userInfo: [.announcement: text, .priority: NSAccessibilityPriorityLevel.high.rawValue])
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = ShotzUI.Motion.fast
            ctx.timingFunction = ShotzUI.Motion.arrive
            animator().alphaValue = 1
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + duration) { [weak self] in
            NSAnimationContext.runAnimationGroup({ ctx in
                ctx.duration = ShotzUI.Motion.standard
                self?.animator().alphaValue = 0
            }, completionHandler: { [weak self] in MainActor.assumeIsolated { self?.removeFromSuperview() } })
        }
    }
}

/// Key caps for shortcuts: "⌘", "⇧", "4" each in a small raised cap.
@MainActor
public final class ShotzKeyCaps: NSView {
    public var keys: [String] { didSet { invalidateIntrinsicContentSize(); needsDisplay = true; setAccessibilityLabel(keys.joined()) } }

    public init(_ keys: [String]) {
        self.keys = keys
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.staticText)
        setAccessibilityLabel(keys.joined())
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) { fatalError("ShotzUI views are built in code") }

    public override var isFlipped: Bool { true }
    static let capHeight: CGFloat = 20
    static let font = NSFont.systemFont(ofSize: 11, weight: .medium)

    private func capWidth(_ key: String) -> CGFloat {
        max(Self.capHeight, ceil((key as NSString).size(withAttributes: [.font: Self.font]).width) + 10)
    }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: keys.map(capWidth).reduce(0, +) + CGFloat(max(keys.count - 1, 0)) * 3, height: Self.capHeight + 1)
    }

    public override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            var x: CGFloat = 0
            for key in keys {
                let w = capWidth(key)
                let r = CGRect(x: x, y: 0, width: w, height: Self.capHeight)
                let bottom = NSBezierPath(roundedRect: r.offsetBy(dx: 0, dy: 1).insetBy(dx: 0.5, dy: 0.5), xRadius: ShotzUI.Radius.small, yRadius: ShotzUI.Radius.small)
                ShotzUI.Palette.border.setFill()
                bottom.fill()
                let cap = NSBezierPath(roundedRect: r.insetBy(dx: 0.5, dy: 0.5), xRadius: ShotzUI.Radius.small, yRadius: ShotzUI.Radius.small)
                ShotzUI.Palette.raised.setFill()
                cap.fill()
                ShotzUI.Palette.border.setStroke()
                cap.lineWidth = 1
                cap.stroke()
                let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: ShotzUI.Palette.textPrimary]
                let s = (key as NSString).size(withAttributes: attrs)
                (key as NSString).draw(at: CGPoint(x: (r.midX - s.width / 2).rounded(), y: (r.midY - s.height / 2).rounded()), withAttributes: attrs)
                x += w + 3
            }
        }
    }
}
