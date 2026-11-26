import AppKit
@testable import ShotzUI

/// A visual sheet of the tokens: colours, type ramp, spacing, radii and control heights.
@MainActor
enum TokensSheet {
    static func make() -> GallerySheet {
        let sheet = GallerySheet(width: 1180)
        typealias P = ShotzUI.Palette
        sheet.title("Colours")
        let colours: [(String, NSColor)] = [
            ("windowBackground", P.windowBackground), ("surface", P.surface), ("surfaceSunken", P.surfaceSunken), ("raised", P.raised),
            ("separator", P.separator), ("border", P.border), ("textPrimary", P.textPrimary), ("textSecondary", P.textSecondary),
            ("textTertiary", P.textTertiary), ("fillHover", P.fillHover), ("fillPressed", P.fillPressed), ("accentFill", P.accentFill),
            ("onAccent", P.onAccent), ("selectedFill", P.selectedFill), ("selectedContent", P.selectedContent), ("focusRing", P.focusRing),
            ("danger", P.danger), ("success", P.success), ("warning", P.warning), ("glassFill", P.glassFill),
        ]
        for chunk in stride(from: 0, to: colours.count, by: 6) {
            let views = colours[chunk..<min(chunk + 6, colours.count)].map { ColourChip(name: $0.0, color: $0.1) as NSView }
            sheet.row("", views, height: 58)
        }
        sheet.title("Type")
        for t in ShotzUI.Typography.allCases {
            let l = NSTextField(labelWithString: "\(t) · \(Int(t.size)) pt \(t.weight == .regular ? "regular" : t.weight == .medium ? "medium" : "semibold")\(t == .value ? " · 0123456789 %" : "")")
            l.font = t.font
            l.textColor = P.textPrimary
            l.sizeToFit()
            sheet.row("", [l], height: max(l.frame.height, 18))
        }
        sheet.title("Spacing · radii · heights")
        let spaces: [(String, CGFloat)] = [("xxs", ShotzUI.Space.xxs), ("xs", ShotzUI.Space.xs), ("s", ShotzUI.Space.s), ("m", ShotzUI.Space.m),
                                           ("l", ShotzUI.Space.l), ("xl", ShotzUI.Space.xl), ("xxl", ShotzUI.Space.xxl)]
        sheet.row("Space", spaces.map { SpaceBar(name: $0.0, value: $0.1) }, height: 40, columnWidth: 110)
        let radii: [(String, CGFloat)] = [("compact", ShotzUI.ControlSize.compact.radius), ("regular", ShotzUI.ControlSize.regular.radius),
                                          ("large", ShotzUI.ControlSize.large.radius), ("tool", ShotzUI.ToolMetrics.radius), ("small", ShotzUI.Radius.small),
                                          ("card", ShotzUI.Radius.card), ("panel", ShotzUI.Radius.panel)]
        sheet.row("Radius", radii.map { RadiusSample(name: $0.0, radius: $0.1) }, height: 52, columnWidth: 110)
        sheet.row("Heights", ShotzUI.ControlSize.allCases.map { ShotzButton(title: "\(Int($0.height)) pt", role: .secondary, size: $0) }
            + [ShotzToolButton(icon: .arrowTool)], height: 40, columnWidth: 110)
        sheet.finish()
        return sheet
    }
}

@MainActor
final class ColourChip: NSView {
    let name: String, color: NSColor
    init(name: String, color: NSColor) {
        self.name = name; self.color = color
        super.init(frame: .zero)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 136, height: 54) }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let r = NSRect(x: 0, y: 0, width: 132, height: 32)
            let path = NSBezierPath(roundedRect: r, xRadius: 6, yRadius: 6)
            ShotzUI.Palette.windowBackground.setFill(); path.fill()
            color.setFill(); path.fill()
            ShotzUI.Palette.border.setStroke(); path.lineWidth = 1; path.stroke()
            (name as NSString).draw(at: NSPoint(x: 0, y: 36), withAttributes: [.font: ShotzUI.Typography.caption.font, .foregroundColor: ShotzUI.Palette.textSecondary])
        }
    }
}

@MainActor
final class SpaceBar: NSView {
    let name: String, value: CGFloat
    init(name: String, value: CGFloat) { self.name = name; self.value = value; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 36) }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ShotzUI.Palette.accentFill.setFill()
            NSRect(x: 0, y: 4, width: value, height: 12).fill()
            ("\(name) \(Int(value))" as NSString).draw(at: NSPoint(x: 0, y: 20), withAttributes: [.font: ShotzUI.Typography.caption.font, .foregroundColor: ShotzUI.Palette.textSecondary])
        }
    }
}

@MainActor
final class RadiusSample: NSView {
    let name: String, radius: CGFloat
    init(name: String, radius: CGFloat) { self.name = name; self.radius = radius; super.init(frame: .zero) }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }
    override var intrinsicContentSize: NSSize { NSSize(width: 100, height: 50) }
    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let path = NSBezierPath(roundedRect: NSRect(x: 0.5, y: 0.5, width: 56, height: 30), xRadius: radius, yRadius: radius)
            ShotzUI.Palette.surface.setFill(); path.fill()
            ShotzUI.Palette.border.setStroke(); path.stroke()
            ("\(name) \(Int(radius))" as NSString).draw(at: NSPoint(x: 0, y: 34), withAttributes: [.font: ShotzUI.Typography.caption.font, .foregroundColor: ShotzUI.Palette.textSecondary])
        }
    }
}
