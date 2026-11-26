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
}
