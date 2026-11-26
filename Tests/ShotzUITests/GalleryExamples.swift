import AppKit
import ShotzCore
@testable import ShotzUI

/// The editor tool strip as a reference: tools in groups with consistent gaps and separators.
@MainActor
final class ToolStripExample: NSView {
    static let groups: [[ShotzIcon]] = [[.select], [.arrowTool, .line, .rectangle, .ellipse, .pen, .highlighter], [.text, .counter], [.redact, .crop, .background]]

    init(selected: ShotzIcon = .arrowTool, hovered: ShotzIcon? = .rectangle) {
        super.init(frame: .zero)
        var x: CGFloat = 0
        for (gi, group) in Self.groups.enumerated() {
            for (i, icon) in group.enumerated() {
                if i > 0 { x += ShotzUI.ToolMetrics.gap }
                let b = ShotzToolButton(icon: icon)
                b.isSelected = icon == selected
                if icon == hovered { b.stateOverride = .hover }
                b.frame = CGRect(x: x, y: 0, width: ShotzUI.ToolMetrics.size, height: ShotzUI.ToolMetrics.size)
                addSubview(b)
                x += ShotzUI.ToolMetrics.size
            }
            if gi < Self.groups.count - 1 {
                x += ShotzUI.Space.s
                let sep = ShotzSeparator()
                sep.frame = CGRect(x: x, y: 0, width: 1, height: ShotzUI.ToolMetrics.size)
                addSubview(sep)
                x += 1 + ShotzUI.Space.s
            }
        }
        setFrameSize(NSSize(width: x, height: ShotzUI.ToolMetrics.size))
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { frame.size }
}

/// A mock title bar (traffic lights, tool strip, action area) to judge the composition in context.
@MainActor
final class TitleBarMock: NSView {
    override init(frame: NSRect) {
        super.init(frame: frame)
        let strip = ToolStripExample()
        strip.frame.origin = CGPoint(x: 84, y: ((frame.height - strip.frame.height) / 2).rounded())
        addSubview(strip)
        let actions = EditorActionArea()
        let size = actions.intrinsicContentSize
        actions.frame = CGRect(x: frame.width - size.width - 12, y: ((frame.height - size.height) / 2).rounded(), width: size.width, height: size.height)
        addSubview(actions)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let path = NSBezierPath(roundedRect: bounds, xRadius: 10, yRadius: 10)
            ShotzUI.Palette.surface.setFill()
            path.fill()
            ShotzUI.Palette.separator.setStroke()
            path.lineWidth = 1
            path.stroke()
            for (i, c) in [NSColor.systemRed, .systemYellow, .systemGreen].enumerated() {
                c.setFill()
                NSBezierPath(ovalIn: CGRect(x: 16 + CGFloat(i) * 20, y: bounds.midY - 6, width: 12, height: 12)).fill()
            }
        }
    }
}

/// Captures a sheet's last row for the accents comparison.
@MainActor
enum AccentRowSnapshot {
    static var rows: [CGImage] = []

    static func capture(_ sheet: GallerySheet, appearance: NSAppearance) -> CGImage {
        sheet.finish()
        let full = sheet.render(appearance: appearance, scale: 2)
        // The last row occupies the bottom 44 pt above the 24-pt bottom margin.
        let rowRect = CGRect(x: 0, y: CGFloat(full.height) - CGFloat((24 + 44) * 2), width: CGFloat(full.width), height: 88)
        return full.cropping(to: rowRect) ?? full
    }

    static func stack() -> CGImage {
        let w = rows.map(\.width).max() ?? 1, h = rows.reduce(0) { $0 + $1.height }
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        var y = h
        for r in rows {
            y -= r.height
            ctx.draw(r, in: CGRect(x: 0, y: y, width: r.width, height: r.height))
        }
        return ctx.makeImage()!
    }
}
