import AppKit
import ImageIO
import ShotzCore
@testable import ShotzUI

/// Builds and renders gallery sheets offline (no window, no app launch).
@MainActor
final class GallerySheet: NSView {
    private var y: CGFloat = 24
    let width: CGFloat
    let labelWidth: CGFloat = 132
    let columnWidth: CGFloat

    init(width: CGFloat = 1180, columnWidth: CGFloat = 150) {
        self.width = width
        self.columnWidth = columnWidth
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        wantsLayer = true
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError() }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            ShotzUI.Palette.windowBackground.setFill()
            bounds.fill()
        }
    }

    func label(_ text: String, style: ShotzUI.Typography = .caption, color: NSColor = ShotzUI.Palette.textSecondary, at p: CGPoint, width: CGFloat? = nil) {
        let l = NSTextField(labelWithString: text)
        l.font = style.font
        l.textColor = color
        l.sizeToFit()
        l.frame = CGRect(x: p.x, y: p.y, width: width ?? l.frame.width, height: l.frame.height)
        addSubview(l)
    }

    func title(_ text: String) {
        y += 12
        label(text, style: .title, color: ShotzUI.Palette.textPrimary, at: CGPoint(x: 24, y: y))
        y += 30
    }

    func header(_ texts: [String], columnWidth: CGFloat? = nil) {
        for (i, t) in texts.enumerated() {
            label(t, at: CGPoint(x: 24 + labelWidth + CGFloat(i) * (columnWidth ?? self.columnWidth), y: y))
        }
        y += 20
    }

    /// A row: a label, then one view per column (each centred vertically in `height`).
    func row(_ name: String, _ views: [NSView], height: CGFloat = 40, columnWidth: CGFloat? = nil) {
        label(name, style: .label, color: ShotzUI.Palette.textPrimary, at: CGPoint(x: 24, y: y + (height - 16) / 2))
        let cw = columnWidth ?? self.columnWidth
        for (i, v) in views.enumerated() {
            let size = v.intrinsicContentSize
            let w = (size.width > 0 ? size.width : cw - 16) + (v is NSTextField ? 4 : 0)
            let h = size.height > 0 ? size.height : height
            v.frame = CGRect(x: 24 + labelWidth + CGFloat(i) * cw, y: y + ((height - h) / 2).rounded(), width: w, height: h)
            addSubview(v)
        }
        y += height + 4
    }

    /// A free-form block: the caller positions `view` (already sized) at the current y.
    func block(_ view: NSView, height: CGFloat, x: CGFloat = 24) {
        view.frame.origin = CGPoint(x: x, y: y)
        addSubview(view)
        y += height + 12
    }

    var cursor: CGFloat { y }
    func spacer(_ h: CGFloat) { y += h }

    func finish() { setFrameSize(NSSize(width: width, height: y + 24)) }

    /// Renders the sheet under `appearance` at `scale` (1 or 2) to a CGImage.
    func render(appearance: NSAppearance, scale: CGFloat) -> CGImage {
        self.appearance = appearance
        layoutSubtreeIfNeeded()
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        rep.size = bounds.size
        markNeedsDisplayRecursively(self)
        cacheDisplay(in: bounds, to: rep)
        return rep.cgImage!
    }

    private func markNeedsDisplayRecursively(_ v: NSView) {
        v.needsDisplay = true
        v.subviews.forEach(markNeedsDisplayRecursively)
    }
}

enum GalleryOutput {
    /// Directories to write to: SHOTZ_UI_GALLERY and optional SHOTZ_UI_GALLERY_COPY.
    static var directories: [URL] {
        let env = ProcessInfo.processInfo.environment
        return [env["SHOTZ_UI_GALLERY"], env["SHOTZ_UI_GALLERY_COPY"]].compactMap { $0 }.map { URL(filePath: $0) }
    }

    static func write(_ image: CGImage, name: String) throws {
        for dir in directories {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let url = dir.appending(path: name)
            guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { continue }
            CGImageDestinationAddImage(dest, image, nil)
            CGImageDestinationFinalize(dest)
        }
    }

    static var appearances: [(String, NSAppearance)] { [
        ("light", NSAppearance(named: .aqua)!), ("dark", NSAppearance(named: .darkAqua)!),
    ] }
    static var highContrast: [(String, NSAppearance)] { [
        ("light-hc", NSAppearance(named: .aqua)!), ("dark-hc", NSAppearance(named: .darkAqua)!), // with increasedContrastOverride
    ] }
    /// The default system blue, pinned so renders and goldens don't depend on the Mac's settings.
    static let blue = NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)
}

/// A neutral fake "image" backdrop for glass controls.
@MainActor
final class ImageBackdrop: NSView {
    override var isFlipped: Bool { true }
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        ctx.clip(to: bounds)
        let colors = [NSColor(srgbRed: 0.55, green: 0.70, blue: 0.86, alpha: 1).cgColor, NSColor(srgbRed: 0.93, green: 0.80, blue: 0.62, alpha: 1).cgColor]
        let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors as CFArray, locations: nil)!
        ctx.drawLinearGradient(g, start: .zero, end: CGPoint(x: bounds.width, y: bounds.height), options: [])
        ctx.setFillColor(NSColor.white.withAlphaComponent(0.85).cgColor)
        ctx.fill(CGRect(x: bounds.width * 0.1, y: bounds.height * 0.2, width: bounds.width * 0.5, height: bounds.height * 0.6))
    }
}
