import AppKit
import ShotzCore

/// Shotz's menu-bar glyph, drawn in code: two stacked snapshot cards, the
/// front one carrying a small annotation stroke. Production is a template
/// image (menu-bar colour); Shotz Dev is tinted amber, matching the DEV band
/// on its app icon, so the two are never confused side by side.
enum StatusItemIcon {
    /// The amber of Shotz Dev's glyph and icon band.
    static let devTint = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)

    static func make(variant: AppVariant = .production) -> NSImage {
        if let art = suppliedGlyph() {
            return variant == .development ? tinted(art, devTint, name: variant.displayName) : named(art, variant.displayName)
        }
        return drawn(variant: variant)
    }

    /// The owner's glyph from `scripts/make-icons.sh --glyph`, as a template image (nil when none was supplied).
    static func suppliedGlyph() -> NSImage? {
        guard let one = MenuBarGlyphArt.png1x.flatMap({ Data(base64Encoded: $0) }).flatMap(NSBitmapImageRep.init(data:)) else {
            return nil
        }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        one.size = image.size
        image.addRepresentation(one)
        if let two = MenuBarGlyphArt.png2x.flatMap({ Data(base64Encoded: $0) }).flatMap(NSBitmapImageRep.init(data:)) {
            two.size = image.size
            image.addRepresentation(two)
        }
        image.isTemplate = true
        return image
    }

    private static func named(_ image: NSImage, _ name: String) -> NSImage {
        image.accessibilityDescription = name
        return image
    }

    /// The template glyph filled with `color` (not a template: keeps its colour in the menu bar).
    private static func tinted(_ template: NSImage, _ color: NSColor, name: String) -> NSImage {
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = name
        return image
    }

    private static func drawn(variant: AppVariant) -> NSImage {
        let ink: NSColor = variant == .development ? devTint : .black
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            ink.setStroke()
            ink.setFill()

            // Back card, peeking out above and to the right.
            let back = NSBezierPath(roundedRect: NSRect(x: 6.25, y: 2.25, width: 10, height: 8), xRadius: 2, yRadius: 2)
            back.lineWidth = 1.5
            back.stroke()

            // Front card: knock the back card out underneath it, then outline.
            let frontRect = NSRect(x: 1.75, y: 6.75, width: 11.5, height: 9)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(roundedRect: frontRect.insetBy(dx: -1.5, dy: -1.5), xRadius: 3.2, yRadius: 3.2).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            let front = NSBezierPath(roundedRect: frontRect, xRadius: 2.2, yRadius: 2.2)
            front.lineWidth = 1.6
            front.stroke()

            // Annotation tick inside the front card.
            let tick = NSBezierPath()
            tick.move(to: NSPoint(x: 4.6, y: 12.6))
            tick.curve(to: NSPoint(x: 10.4, y: 9.6), controlPoint1: NSPoint(x: 6.4, y: 9.4), controlPoint2: NSPoint(x: 8.2, y: 12.8))
            tick.lineWidth = 1.6
            tick.lineCapStyle = .round
            tick.stroke()
            return true
        }
        image.isTemplate = variant == .production
        image.accessibilityDescription = variant.displayName
        return image
    }
}
