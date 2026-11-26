import AnnotationKit
import AppKit

/// Small template images drawn in code for options that SF Symbols do not
/// cover exactly (Shotz's own artwork).
@MainActor enum EditorIcons {
    static let size = NSSize(width: 22, height: 16)

    private static func template(_ draw: @escaping (CGRect) -> Void) -> NSImage {
        let image = NSImage(size: size, flipped: true) { rect in
            NSColor.black.set()
            draw(rect)
            return true
        }
        image.isTemplate = true
        return image
    }

    static func thickness(_ step: Int) -> NSImage {
        let widths: [CGFloat] = [1, 2, 3, 4.5, 6.5]
        let w = widths[min(max(step, 0), widths.count - 1)]
        return template { r in
            let p = NSBezierPath(roundedRect: NSRect(x: 3, y: r.midY - w / 2, width: r.width - 6, height: w), xRadius: w / 2, yRadius: w / 2)
            p.fill()
        }
    }

    static func arrow(_ style: ArrowStyle) -> NSImage {
        template { r in
            let start = CGPoint(x: 3, y: r.maxY - 3), end = CGPoint(x: r.maxX - 4, y: 4)
            let path = NSBezierPath()
            path.lineWidth = 1.6
            path.lineCapStyle = .round
            switch style {
            case .curved:
                path.move(to: start)
                path.curve(to: end, controlPoint1: CGPoint(x: 4, y: 3), controlPoint2: CGPoint(x: 8, y: 3))
            case .tapered:
                let body = NSBezierPath()
                body.move(to: CGPoint(x: start.x - 0.3, y: start.y - 0.3))
                body.line(to: CGPoint(x: end.x - 4, y: end.y + 1))
                body.line(to: CGPoint(x: end.x - 1, y: end.y + 4))
                body.close()
                body.fill()
            default:
                path.move(to: start)
                path.line(to: end)
            }
            path.stroke()
            head(at: end, from: style == .curved ? CGPoint(x: 8, y: 3) : start)
            if style == .doubleHeaded { head(at: start, from: end) }
            if style == .lineWithDot {
                NSBezierPath(ovalIn: NSRect(x: start.x - 2.5, y: start.y - 2.5, width: 5, height: 5)).fill()
            }
        }
    }

    private static func head(at tip: CGPoint, from tail: CGPoint) {
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let len: CGFloat = 6, spread: CGFloat = 0.5
        let p = NSBezierPath()
        p.move(to: tip)
        p.line(to: CGPoint(x: tip.x - len * cos(angle - spread), y: tip.y - len * sin(angle - spread)))
        p.line(to: CGPoint(x: tip.x - len * cos(angle + spread), y: tip.y - len * sin(angle + spread)))
        p.close()
        p.fill()
    }

    static func fill(_ mode: ObjectStyle.FillMode, ellipse: Bool = false) -> NSImage {
        template { r in
            let box = NSRect(x: 4, y: 2.5, width: r.width - 8, height: r.height - 5)
            let shape = ellipse ? NSBezierPath(ovalIn: box) : NSBezierPath(roundedRect: box, xRadius: 2, yRadius: 2)
            shape.lineWidth = 1.5
            switch mode {
            case .outline:
                shape.stroke()
            case .filled:
                shape.fill()
            case .outlineTranslucentFill:
                NSColor.black.withAlphaComponent(0.35).setFill()
                shape.fill()
                NSColor.black.setStroke()
                shape.stroke()
            }
        }
    }

    static func dash(_ dash: ObjectStyle.Dash) -> NSImage {
        template { r in
            let p = NSBezierPath()
            p.lineWidth = 2
            p.move(to: CGPoint(x: 3, y: r.midY))
            p.line(to: CGPoint(x: r.maxX - 3, y: r.midY))
            if dash == .dashed { p.setLineDash([3, 2.5], count: 2, phase: 0) }
            p.stroke()
        }
    }

    static func textDecoration(_ d: TextStyle.Decoration) -> NSImage {
        let image = NSImage(size: size, flipped: true) { r in
            let font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            let pill = NSBezierPath(roundedRect: r.insetBy(dx: 1, dy: 2), xRadius: 5, yRadius: 5)
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
            switch d {
            case .plain: break
            case .outlined:
                attrs[.strokeWidth] = 3
                attrs[.strokeColor] = NSColor.black
            case .solidPill:
                NSColor.black.setFill(); pill.fill()
                attrs[.foregroundColor] = NSColor.clear
            case .translucentPill:
                NSColor.black.withAlphaComponent(0.35).setFill(); pill.fill()
            }
            let s = NSAttributedString(string: "Aa", attributes: attrs)
            let sz = s.size()
            if d == .solidPill {
                // Knock the letters out of the pill.
                NSGraphicsContext.current?.compositingOperation = .destinationOut
                NSAttributedString(string: "Aa", attributes: [.font: font, .foregroundColor: NSColor.black])
                    .draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            } else {
                s.draw(at: CGPoint(x: r.midX - sz.width / 2, y: r.midY - sz.height / 2))
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// A filled colour circle for the preset swatches (not a template).
    static func swatch(_ color: NSColor, selected: Bool) -> NSImage {
        NSImage(size: NSSize(width: 18, height: 18), flipped: true) { r in
            let inner = r.insetBy(dx: 3, dy: 3)
            color.setFill()
            NSBezierPath(ovalIn: inner).fill()
            NSColor.separatorColor.setStroke()
            let border = NSBezierPath(ovalIn: inner.insetBy(dx: 0.25, dy: 0.25))
            border.lineWidth = 0.5
            border.stroke()
            if selected {
                NSColor.controlAccentColor.setStroke()
                let ring = NSBezierPath(ovalIn: r.insetBy(dx: 0.75, dy: 0.75))
                ring.lineWidth = 1.5
                ring.stroke()
            }
            return true
        }
    }
}
