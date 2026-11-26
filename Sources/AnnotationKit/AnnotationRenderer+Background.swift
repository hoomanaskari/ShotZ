import CoreGraphics

extension AnnotationRenderer {
    struct ShadowParameters {
        var offset: CGSize
        var blur: CGFloat
        var color: CGColor
    }

    static func shadowParameters(_ shadow: BackgroundStyle.Shadow, imageSize: CGSize) -> ShadowParameters? {
        let long = max(imageSize.width, imageSize.height)
        switch shadow {
        case .off:
            return nil
        case .soft:
            return ShadowParameters(offset: CGSize(width: 0, height: long * 0.008), blur: long * 0.03,
                                    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.28))
        case .strong:
            return ShadowParameters(offset: CGSize(width: 0, height: long * 0.016), blur: long * 0.05,
                                    color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.5))
        }
    }

    /// Fills `rect` (top-left space) with a background fill. `.none` leaves it transparent.
    public static func drawBackgroundFill(_ fill: BackgroundStyle.Fill, in rect: CGRect, ctx: CGContext) {
        switch fill {
        case .none:
            return
        case .solid(let color):
            ctx.setFillColor(color.cgColor)
            ctx.fill(rect)
        case .gradient(let g):
            let space = ctx.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
            guard let gradient = CGGradient(colorsSpace: space, colors: [g.from.cgColor, g.to.cgColor] as CFArray, locations: [0, 1])
            else { return }
            // Angle in degrees in top-left space: 0 = left→right, 90 = top→bottom.
            let a = g.angle * .pi / 180
            let d = CGVector(dx: cos(a), dy: sin(a))
            let half = abs(rect.width / 2 * d.dx) + abs(rect.height / 2 * d.dy)
            let c = CGPoint(x: rect.midX, y: rect.midY)
            ctx.saveGState()
            ctx.clip(to: rect)
            ctx.drawLinearGradient(gradient, start: Geometry.offset(c, d, -half), end: Geometry.offset(c, d, half),
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            ctx.restoreGState()
        }
    }

    /// Draws the image group's drop shadow. Blurring a 5K layer at full resolution costs hundreds
    /// of milliseconds, so the shadow is rendered into a small bitmap (≈12 px of blur there) and
    /// scaled up; a soft shadow loses nothing. The casting shape is drawn far off-canvas with the
    /// offset compensated, so only the shadow lands. Images with alpha (window captures) cast
    /// their real silhouette; opaque images cast the rounded rect.
    static func drawShadow(_ shadow: ShadowParameters, image: CGImage, document: AnnotationDocument, layout: BackgroundLayout,
                           radius: CGFloat, outputScale: CGFloat, in ctx: CGContext) {
        let canvas = layout.canvasSize
        let k = min(1, max(12 / max(shadow.blur, 1), 1 / 32)) * min(outputScale, 1)
        let w = max(Int((canvas.width * k).rounded(.up)), 1), h = max(Int((canvas.height * k).rounded(.up)), 1)
        guard let small = Redactor.bitmap(width: w, height: h, space: Redactor.workingSpace(of: image)) else { return }
        small.interpolationQuality = .medium
        small.translateBy(x: 0, y: CGFloat(h))
        small.scaleBy(x: k, y: -k)
        let far = canvas.width * 2 + shadow.blur * 4
        small.setShadowInUserSpace(offset: CGSize(width: shadow.offset.width - far, height: shadow.offset.height),
                                   blur: shadow.blur, color: shadow.color)
        small.translateBy(x: far, y: 0)
        let frame = layout.imageFrame
        let shape = radius > 0
            ? CGPath(roundedRect: frame, cornerWidth: radius, cornerHeight: radius, transform: nil)
            : CGPath(rect: frame, transform: nil)
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            small.addPath(shape)
            small.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 1))
            small.fillPath()
        default:
            small.beginTransparencyLayer(auxiliaryInfo: nil)
            small.addPath(shape)
            small.clip()
            let rect = document.imageRect
            small.drawFlipped(image, in: CGRect(x: frame.minX - rect.minX, y: frame.minY - rect.minY,
                                                width: document.pixelSize.width, height: document.pixelSize.height))
            small.endTransparencyLayer()
        }
        guard let shadowImage = small.makeImage() else { return }
        ctx.saveGState()
        ctx.interpolationQuality = .high
        ctx.drawFlipped(shadowImage, in: CGRect(x: 0, y: 0, width: CGFloat(w) / k, height: CGFloat(h) / k))
        ctx.restoreGState()
    }
}
