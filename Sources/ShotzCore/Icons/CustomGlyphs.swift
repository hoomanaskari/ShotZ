import CoreGraphics

/// Shotz's own glyphs, drawn on Phosphor's 256-unit grid (y down) with its 16-unit stroke,
/// round caps and joins, so they sit naturally beside the Phosphor icons. Arrowheads are solid
/// (with a shallow notch and softened corners): at 16–18 pt an open chevron reads as a line.
enum CustomGlyphs {
    private typealias G = IconGlyph
    private static let w = IconGlyph.stroke

    static func layers(for icon: ShotzIcon) -> [IconLayer] {
        switch icon {
        case .arrowTool, .arrowStraight: return [IconLayer(path: straightArrow())]
        case .line:
            // A plain diagonal (no end dots), the same length and weight as the arrow tool's shaft.
            return [IconLayer(path: G.stroked(G.line(CGPoint(x: 52, y: 204), CGPoint(x: 204, y: 52))))]
        case .pen:
            // One smooth freehand stroke: lighter than a scribble, same 16-unit weight as its neighbours.
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 40, y: 172))
            p.addCurve(to: CGPoint(x: 128, y: 128), control1: CGPoint(x: 64, y: 92), control2: CGPoint(x: 104, y: 92))
            p.addCurve(to: CGPoint(x: 216, y: 84), control1: CGPoint(x: 152, y: 164), control2: CGPoint(x: 192, y: 164))
            return [IconLayer(path: G.stroked(p))]
        case .highlighter:
            return [IconLayer(path: highlighterTool())]
        case .more:
            // Three dots large enough to read at 16 pt (Phosphor's are 24 units; these are 36).
            return [IconLayer(path: G.union([CGFloat(56), 128, 200].map {
                CGPath(ellipseIn: CGRect(x: $0 - 18, y: 110, width: 36, height: 36), transform: nil)
            }))]
        case .arrowCurved: return [IconLayer(path: curvedArrow())]
        case .arrowTapered: return [IconLayer(path: taperedArrow())]
        case .arrowDoubleHeaded: return [IconLayer(path: doubleArrow())]
        case .arrowLineWithDot: return [IconLayer(path: dotArrow())]
        case .fillOutline: return [IconLayer(path: G.stroked(G.roundedRect(boxRect, 20)))]
        case .fillSolid: return [IconLayer(path: G.roundedRect(boxRect.insetBy(dx: -w / 2, dy: -w / 2), 28))]
        case .fillOutlineTranslucent:
            return [IconLayer(path: G.roundedRect(boxRect.insetBy(dx: w / 2, dy: w / 2), 12), opacity: 0.35),
                    IconLayer(path: G.stroked(G.roundedRect(boxRect, 20)))]
        case .lineSolid: return [IconLayer(path: G.stroked(G.line(diagonalStart, diagonalEnd)))]
        case .lineDashed:
            // Three dashes, a dash at each end: 3d + 2g = length, visible gap g − stroke.
            let length = hypot(diagonalEnd.x - diagonalStart.x, diagonalEnd.y - diagonalStart.y)
            let gap: CGFloat = 48, dash = (length - 2 * gap) / 3
            let dashed = G.line(diagonalStart, diagonalEnd).copy(dashingWithPhase: 0, lengths: [dash, gap])
            return [IconLayer(path: G.stroked(dashed))]
        case .textPlain: return [IconLayer(path: G.stroked(letterT(bigT), width: 20))]
        case .textOutlined:
            let thick = G.stroked(letterT(bigT), width: 56, cap: .square)
            return [IconLayer(path: G.stroked(thick.normalized(using: .winding), width: 14))]
        case .textSolidPill:
            return [IconLayer(path: pill.subtracting(G.stroked(letterT(smallT), width: 22), using: .winding))]
        case .textTranslucentPill:
            return [IconLayer(path: pill, opacity: 0.35), IconLayer(path: G.stroked(letterT(smallT), width: 22))]
        case .highlightFreehand:
            let wave = CGMutablePath()
            wave.move(to: CGPoint(x: 52, y: 140))
            wave.addCurve(to: CGPoint(x: 204, y: 124), control1: CGPoint(x: 100, y: 96), control2: CGPoint(x: 156, y: 172))
            return [IconLayer(path: G.stroked(wave, width: 68), opacity: 0.4),
                    IconLayer(path: G.stroked(G.line(CGPoint(x: 60, y: 132), CGPoint(x: 196, y: 132))))]
        case .highlightRect:
            return [IconLayer(path: G.roundedRect(CGRect(x: 32, y: 92, width: 192, height: 72), 14), opacity: 0.4),
                    IconLayer(path: G.stroked(G.line(CGPoint(x: 60, y: 128), CGPoint(x: 196, y: 128))))]
        case .redactPixelate: return pixelGrid()
        case .redactBlur:
            return [(96, 0.16), (72, 0.32), (48, 0.6), (24, 1.0)].map { r, o in
                IconLayer(path: CGPath(ellipseIn: CGRect(x: 128 - r, y: 128 - r, width: 2 * r, height: 2 * r), transform: nil), opacity: o)
            }
        case .redactSolid:
            return [IconLayer(path: G.union([
                G.roundedRect(CGRect(x: 32, y: 100, width: 192, height: 56), 10),
                G.stroked(G.line(CGPoint(x: 56, y: 60), CGPoint(x: 200, y: 60))),
                G.stroked(G.line(CGPoint(x: 56, y: 196), CGPoint(x: 156, y: 196))),
            ]))]
        case .thickness1, .thickness2, .thickness3, .thickness4, .thickness5:
            let widths: [CGFloat] = [10, 18, 30, 46, 66]
            let i = ShotzIcon.thicknessSteps.firstIndex(of: icon) ?? 0
            return [IconLayer(path: G.stroked(G.line(CGPoint(x: 44, y: 128), CGPoint(x: 212, y: 128)), width: widths[i]))]
        case .lineThickness:
            return [IconLayer(path: G.union([
                G.stroked(G.line(CGPoint(x: 48, y: 64), CGPoint(x: 208, y: 64)), width: 8),
                G.stroked(G.line(CGPoint(x: 48, y: 122), CGPoint(x: 208, y: 122)), width: 18),
                G.stroked(G.line(CGPoint(x: 48, y: 190), CGPoint(x: 208, y: 190)), width: 32),
            ]))]
        case .cornerRadius:
            let p = CGMutablePath()
            p.move(to: CGPoint(x: 56, y: 216))
            p.addLine(to: CGPoint(x: 56, y: 128))
            p.addArc(tangent1End: CGPoint(x: 56, y: 56), tangent2End: CGPoint(x: 128, y: 56), radius: 72)
            p.addLine(to: CGPoint(x: 216, y: 56))
            let dots = [CGPoint(x: 216, y: 216), CGPoint(x: 136, y: 216), CGPoint(x: 216, y: 136)].map {
                CGPath(ellipseIn: CGRect(x: $0.x - 10, y: $0.y - 10, width: 20, height: 20), transform: nil)
            }
            return [IconLayer(path: G.union([G.stroked(p)] + dots))]
        case .shadow:
            let square = G.stroked(G.roundedRect(CGRect(x: 40, y: 40, width: 136, height: 136), 16))
            let shadow = CGMutablePath()
            shadow.move(to: CGPoint(x: 210, y: 84))
            shadow.addLine(to: CGPoint(x: 210, y: 194))
            shadow.addArc(tangent1End: CGPoint(x: 210, y: 210), tangent2End: CGPoint(x: 194, y: 210), radius: 16)
            shadow.addLine(to: CGPoint(x: 84, y: 210))
            return [IconLayer(path: G.stroked(shadow, width: 22), opacity: 0.45), IconLayer(path: square)]
        case .background:
            return [IconLayer(path: G.roundedRect(CGRect(x: 24, y: 40, width: 208, height: 176), 28), opacity: 0.32),
                    IconLayer(path: G.roundedRect(CGRect(x: 68, y: 80, width: 120, height: 96), 12))]
        default:
            return []
        }
    }

    // MARK: Geometry

    private static let boxRect = CGRect(x: 36, y: 60, width: 184, height: 136)
    private static let diagonalStart = CGPoint(x: 48, y: 208)
    private static let diagonalEnd = CGPoint(x: 208, y: 48)
    private static var pill: CGPath { IconGlyph.roundedRect(CGRect(x: 20, y: 60, width: 216, height: 136), 44) }
    private static let bigT = (bar: (CGPoint(x: 72, y: 68), CGPoint(x: 184, y: 68)), stem: (CGPoint(x: 128, y: 68), CGPoint(x: 128, y: 192)))
    private static let smallT = (bar: (CGPoint(x: 90, y: 98), CGPoint(x: 166, y: 98)), stem: (CGPoint(x: 128, y: 98), CGPoint(x: 128, y: 162)))

    private static func letterT(_ t: (bar: (CGPoint, CGPoint), stem: (CGPoint, CGPoint))) -> CGPath {
        let p = CGMutablePath()
        p.move(to: t.bar.0); p.addLine(to: t.bar.1)
        p.move(to: t.stem.0); p.addLine(to: t.stem.1)
        return p
    }

    private static func vector(_ a: CGPoint, _ b: CGPoint) -> CGVector { CGVector(dx: b.x - a.x, dy: b.y - a.y) }

    private static func straightArrow() -> CGPath {
        let tail = CGPoint(x: 48, y: 208), tip = CGPoint(x: 212, y: 44)
        let head = G.arrowHead(tip: tip, direction: vector(tail, tip), length: 92, halfWidth: 52)
        return G.union([G.stroked(G.line(tail, head.shaftEnd)), head.head])
    }

    private static func curvedArrow() -> CGPath {
        let start = CGPoint(x: 48, y: 212), tip = CGPoint(x: 220, y: 76)
        let dir = CGVector(dx: 1, dy: -0.08)
        let head = G.arrowHead(tip: tip, direction: dir, length: 88, halfWidth: 50)
        let len = hypot(dir.dx, dir.dy)
        let c2 = CGPoint(x: head.shaftEnd.x - dir.dx / len * 76, y: head.shaftEnd.y - dir.dy / len * 76)
        let curve = CGMutablePath()
        curve.move(to: start)
        curve.addCurve(to: head.shaftEnd, control1: CGPoint(x: 48, y: 136), control2: c2)
        return G.union([G.stroked(curve), head.head])
    }

    private static func taperedArrow() -> CGPath {
        let tail = CGPoint(x: 44, y: 212), tip = CGPoint(x: 214, y: 42)
        let d = vector(tail, tip)
        let head = G.arrowHead(tip: tip, direction: d, length: 100, halfWidth: 60)
        let len = hypot(d.dx, d.dy)
        let n = CGVector(dx: -d.dy / len, dy: d.dx / len)
        func off(_ p: CGPoint, _ k: CGFloat) -> CGPoint { CGPoint(x: p.x + n.dx * k, y: p.y + n.dy * k) }
        let body = G.polyline([off(tail, 3), off(head.shaftEnd, 17), off(head.shaftEnd, -17), off(tail, -3)], closed: true)
        let cap = CGPath(ellipseIn: CGRect(x: tail.x - 4, y: tail.y - 4, width: 8, height: 8), transform: nil)
        return G.union([body, body.copy(strokingWithWidth: 4, lineCap: .round, lineJoin: .round, miterLimit: 10), cap, head.head])
    }

    private static func doubleArrow() -> CGPath {
        let a = CGPoint(x: 44, y: 212), b = CGPoint(x: 212, y: 44)
        let headB = G.arrowHead(tip: b, direction: vector(a, b), length: 80, halfWidth: 46)
        let headA = G.arrowHead(tip: a, direction: vector(b, a), length: 80, halfWidth: 46)
        return G.union([G.stroked(G.line(headA.shaftEnd, headB.shaftEnd)), headA.head, headB.head])
    }

    private static func dotArrow() -> CGPath {
        let dot = CGPoint(x: 64, y: 192), tip = CGPoint(x: 212, y: 44)
        let head = G.arrowHead(tip: tip, direction: vector(dot, tip), length: 88, halfWidth: 50)
        let r: CGFloat = 24
        return G.union([G.stroked(G.line(dot, head.shaftEnd)), head.head,
                        CGPath(ellipseIn: CGRect(x: dot.x - r, y: dot.y - r, width: 2 * r, height: 2 * r), transform: nil)])
    }

    /// A chisel marker drawn as a light outline (body, collar and tip) over a short stroke of ink,
    /// tilted 45°: reads as a highlighter without the heavy fill of the pack glyph.
    private static func highlighterTool() -> CGPath {
        let body = CGMutablePath()
        // Body: an outlined rounded bar from upper-right towards lower-left.
        body.addPath(G.roundedRect(CGRect(x: 104, y: 28, width: 64, height: 112), 14))
        body.move(to: CGPoint(x: 104, y: 112)); body.addLine(to: CGPoint(x: 168, y: 112))   // collar
        body.move(to: CGPoint(x: 112, y: 140)); body.addLine(to: CGPoint(x: 120, y: 172))   // tip sides
        body.addLine(to: CGPoint(x: 152, y: 172)); body.addLine(to: CGPoint(x: 160, y: 140))
        var rotate = CGAffineTransform(translationX: 136, y: 100).rotated(by: .pi / 4).translatedBy(x: -136, y: -100)
        let tilted = body.copy(using: &rotate) ?? body
        let ink = G.line(CGPoint(x: 40, y: 220), CGPoint(x: 112, y: 220))
        return G.union([G.stroked(tilted), G.stroked(ink, width: 20)])
    }

    private static func pixelGrid() -> [IconLayer] {
        let pattern: [[CGFloat]] = [[1, 0.4, 0.75, 0.25], [0.5, 0.9, 0.3, 0.7], [0.8, 0.2, 1, 0.45], [0.35, 0.65, 0.5, 0.95]]
        let cell: CGFloat = 40, gap: CGFloat = 8, origin: CGFloat = 128 - (4 * cell + 3 * gap) / 2
        var layers: [IconLayer] = []
        for (r, row) in pattern.enumerated() {
            for (c, o) in row.enumerated() {
                let rect = CGRect(x: origin + CGFloat(c) * (cell + gap), y: origin + CGFloat(r) * (cell + gap), width: cell, height: cell)
                layers.append(IconLayer(path: G.roundedRect(rect, 6), opacity: o))
            }
        }
        return layers
    }
}
