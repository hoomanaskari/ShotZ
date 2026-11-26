import AppKit
import CoreGraphics

extension ShotzIcon {
    /// The icon's layers fitted (aspect-preserving, centred) into `rect`.
    /// - Parameter flipped: false (default) for y-up spaces (AppKit views, CALayers on macOS);
    ///   true for top-left spaces (flipped views, `isGeometryFlipped` layers).
    public func layers(in rect: CGRect, flipped: Bool = false) -> [IconLayer] {
        let s = min(rect.width, rect.height) / 256
        let ox = rect.midX - 128 * s, oy = rect.midY - 128 * s
        var t = flipped
            ? CGAffineTransform(a: s, b: 0, c: 0, d: s, tx: ox, ty: oy)
            : CGAffineTransform(a: s, b: 0, c: 0, d: -s, tx: ox, ty: oy + 256 * s)
        return glyphLayers.map { layer in
            IconLayer(path: layer.path.copy(using: &t) ?? layer.path, opacity: layer.opacity)
        }
    }

    /// The whole icon as one path (all layers merged, translucent ones included at full
    /// strength), fitted into `rect`. Fill with the non-zero rule. For translucent parts use
    /// `layers(in:flipped:)` or `image(pointSize:)`.
    public func path(in rect: CGRect) -> CGPath {
        path(in: rect, flipped: false)
    }

    public func path(in rect: CGRect, flipped: Bool) -> CGPath {
        let layers = layers(in: rect, flipped: flipped)
        if layers.count == 1, let only = layers.first { return only.path }
        return IconGlyph.union(layers.map(\.path))
    }

    /// Draws the icon into `ctx` filling `rect` with `color` (translucent layers keep their opacity).
    public func draw(in ctx: CGContext, rect: CGRect, color: CGColor, flipped: Bool = false) {
        ctx.saveGState()
        defer { ctx.restoreGState() }
        ctx.setFillColor(color)
        for layer in layers(in: rect, flipped: flipped) {
            ctx.saveGState()
            ctx.setAlpha(layer.opacity)
            ctx.addPath(layer.path)
            ctx.fillPath(using: .winding)
            ctx.restoreGState()
        }
    }

    /// A template image `pointSize` × `pointSize` points (tinted by AppKit like SF Symbols),
    /// drawn from vectors at whatever backing scale it lands on, with an accessibility description.
    public func image(pointSize: CGFloat) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let icon = self
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            icon.draw(in: ctx, rect: rect, color: CGColor(gray: 0, alpha: 1))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = accessibilityDescription
        return image
    }
}
