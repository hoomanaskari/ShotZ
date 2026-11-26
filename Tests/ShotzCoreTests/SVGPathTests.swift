import CoreGraphics
import Testing
@testable import ShotzCore

struct SVGPathTests {
    func box(_ d: String) throws -> CGRect { try SVGPath.parse(d).boundingBoxOfPath }
    func close(_ a: CGRect, _ b: CGRect, _ tol: CGFloat = 0.01) -> Bool {
        abs(a.minX - b.minX) < tol && abs(a.minY - b.minY) < tol && abs(a.maxX - b.maxX) < tol && abs(a.maxY - b.maxY) < tol
    }

    @Test func linesAbsoluteRelativeAndImplicit() throws {
        #expect(close(try box("M10,10 L20,30"), CGRect(x: 10, y: 10, width: 10, height: 20)))
        #expect(close(try box("m10 10 l10 20 h5 v-40"), CGRect(x: 10, y: -10, width: 15, height: 40)))
        // Implicit repeats: after M the pairs are line-tos; after l they stay relative.
        #expect(close(try box("M0 0 10 0 10 10"), CGRect(x: 0, y: 0, width: 10, height: 10)))
        #expect(close(try box("m5 5 5 0 0 5"), CGRect(x: 5, y: 5, width: 5, height: 5)))
        #expect(close(try box("M0,0H8V8H0Z"), CGRect(x: 0, y: 0, width: 8, height: 8)))
    }

    @Test func compactNumbers() throws {
        // "-.5.5" is two numbers; exponents; signs as separators.
        #expect(close(try box("M-.5.5L1e1-2"), CGRect(x: -0.5, y: -2, width: 10.5, height: 2.5)))
        #expect(close(try box("M0 0L+3 4"), CGRect(x: 0, y: 0, width: 3, height: 4)))
    }

    @Test func curvesAndReflection() throws {
        // Cubic with S reflecting the previous control point: symmetric hump.
        let p = try SVGPath.parse("M0,0 C0,-10 10,-10 10,0 S20,10 20,0")
        let b = p.boundingBoxOfPath
        #expect(abs(b.minY + 7.5) < 0.01 && abs(b.maxY - 7.5) < 0.01)
        let q = try SVGPath.parse("M0 0 Q5 -10 10 0 T20 0")
        #expect(abs(q.boundingBoxOfPath.minY + 5) < 0.01 && abs(q.boundingBoxOfPath.maxY - 5) < 0.01)
    }

    @Test func arcs() throws {
        // SVG y-down space: sweep 1 is clockwise on screen, so left→right passes over the top.
        let half = try box("M0,0 A10,10 0 0,1 20,0")
        #expect(close(half, CGRect(x: 0, y: -10, width: 20, height: 10), 0.05), "\(half)")
        let other = try box("M0,0 A10,10 0 0,0 20,0")
        #expect(close(other, CGRect(x: 0, y: 0, width: 20, height: 10), 0.05), "\(other)")
        // Compact flags ("11") and a radius too small: scaled up to span the endpoints.
        let compact = try box("M0 0a5 5 0 1120 0")
        #expect(close(compact, CGRect(x: 0, y: -10, width: 20, height: 10), 0.05), "\(compact)")
        // Large arc + sweep picks the centre (10,10): a 270° arc.
        let large = try box("M10,0 A10,10 0 1,1 0,10")
        #expect(close(large, CGRect(x: 0, y: 0, width: 20, height: 20), 0.05), "\(large)")
        // Zero radius is a straight line.
        #expect(close(try box("M0,0 A0,5 0 0,1 10,10"), CGRect(x: 0, y: 0, width: 10, height: 10)))
    }

    @Test func errors() {
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("L10 10") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M10 x") }
        #expect(throws: SVGPath.ParseError.self) { try SVGPath.parse("M10") }
        #expect((try? SVGPath.parse(""))?.isEmpty == true)
    }
}
