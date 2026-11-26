import CoreGraphics
import Foundation

/// Glyph construction on the 256-unit design grid (y down), shared by Phosphor and custom glyphs.
enum IconGlyph {
    /// Phosphor regular's stroke weight on the 256 grid.
    static let stroke: CGFloat = 16

    /// Parsed Phosphor paths, built once.
    private static let phosphorLayers: [String: IconLayer] = {
        var out: [String: IconLayer] = [:]
        for (name, data) in PhosphorGlyphs.pathData {
            // Generated from vendored SVGs and covered by tests; a parse failure would be a
            // generator bug, so the icon falls back to empty rather than crashing the app.
            out[name] = IconLayer(path: (try? SVGPath.parse(data)) ?? CGMutablePath())
        }
        return out
    }()

    static func phosphor(_ name: String) -> [IconLayer] {
        [phosphorLayers[name] ?? IconLayer(path: CGMutablePath())]
    }

    // MARK: Builders for custom glyphs

    /// A centre line stroked like Phosphor regular (16 units, round caps and joins) as a fill.
    static func stroked(_ path: CGPath, width: CGFloat = stroke, cap: CGLineCap = .round) -> CGPath {
        path.copy(strokingWithWidth: width, lineCap: cap, lineJoin: .round, miterLimit: 10)
    }

    static func line(_ a: CGPoint, _ b: CGPoint) -> CGPath {
        let p = CGMutablePath()
        p.move(to: a)
        p.addLine(to: b)
        return p
    }

    static func polyline(_ pts: [CGPoint], closed: Bool = false) -> CGPath {
        let p = CGMutablePath()
        p.addLines(between: pts)
        if closed { p.closeSubpath() }
        return p
    }

    static func roundedRect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
        CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// Union of several filled shapes into one clean outline.
    static func union(_ paths: [CGPath]) -> CGPath {
        guard var result = paths.first?.normalized(using: .winding) else { return CGMutablePath() }
        for p in paths.dropFirst() { result = result.union(p, using: .winding) }
        return result
    }

    /// A solid arrowhead with a shallow notch and softened corners, pointing along `direction`.
    /// Returns the head and the point where a shaft should end (inside the notch).
    static func arrowHead(tip: CGPoint, direction d: CGVector, length: CGFloat, halfWidth: CGFloat)
        -> (head: CGPath, shaftEnd: CGPoint) {
        let len = max(hypot(d.dx, d.dy), 1e-6)
        let u = CGVector(dx: d.dx / len, dy: d.dy / len)
        let n = CGVector(dx: -u.dy, dy: u.dx)
        // Inset the outline by the rounding radius so the softened head keeps its nominal size.
        let round: CGFloat = 5
        let t = CGPoint(x: tip.x - u.dx * round * 1.6, y: tip.y - u.dy * round * 1.6)
        let base = CGPoint(x: tip.x - u.dx * length, y: tip.y - u.dy * length)
        let notch = CGPoint(x: base.x + u.dx * length * 0.22, y: base.y + u.dy * length * 0.22)
        let hw = halfWidth - round
        let w1 = CGPoint(x: base.x + n.dx * hw, y: base.y + n.dy * hw)
        let w2 = CGPoint(x: base.x - n.dx * hw, y: base.y - n.dy * hw)
        let shape = polyline([t, w1, notch, w2], closed: true)
        let head = union([shape, shape.copy(strokingWithWidth: round * 2, lineCap: .round, lineJoin: .round, miterLimit: 10)])
        let shaftEnd = CGPoint(x: notch.x + u.dx * 4, y: notch.y + u.dy * 4)
        return (head, shaftEnd)
    }
}
