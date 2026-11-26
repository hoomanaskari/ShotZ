import AppKit

/// Shotz's menu-bar glyph, drawn in code as a template image: two stacked
/// snapshot cards, the front one carrying a small annotation stroke.
enum StatusItemIcon {
    static func make() -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            NSColor.black.setStroke()
            NSColor.black.setFill()

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
        image.isTemplate = true
        image.accessibilityDescription = "Shotz"
        return image
    }
}
