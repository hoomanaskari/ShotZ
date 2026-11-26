import CoreGraphics
import Foundation

/// A small parser for SVG path data (`d` attributes): every command (M L H V C S Q T A Z, absolute
/// and relative), implicit command repetition and compact number syntax ("-.5.5", "1e-3",
/// arc flags written without separators). Coordinates are returned as written (SVG space, y down).
public enum SVGPath {
    public enum ParseError: Error, Equatable, Sendable {
        case unexpectedCharacter(Character, offset: Int)
        case missingNumber(command: Character, offset: Int)
        case noCurrentPoint(command: Character)
    }

    public static func parse(_ data: String) throws -> CGPath {
        var scanner = Scanner(Array(data.utf8))
        let path = CGMutablePath()
        var current = CGPoint.zero, subpathStart = CGPoint.zero
        var lastControl: CGPoint?        // for S/s and T/t reflection
        var lastCommand: UInt8 = 0
        var hasCurrent = false

        while scanner.skipSeparators() {
            var command: UInt8
            if let c = scanner.peek(), isCommand(c) {
                command = c
                scanner.advance()
            } else if lastCommand != 0, scanner.peekIsNumberStart() {
                // Implicit repetition; after M/m the repeats are L/l.
                command = lastCommand == UInt8(ascii: "M") ? UInt8(ascii: "L") : lastCommand == UInt8(ascii: "m") ? UInt8(ascii: "l") : lastCommand
            } else {
                let c = scanner.peek().map { Character(UnicodeScalar($0)) } ?? " "
                throw ParseError.unexpectedCharacter(c, offset: scanner.index)
            }
            let relative = command >= UInt8(ascii: "a")
            let upper = relative ? command - 32 : command
            let ch = Character(UnicodeScalar(command))
            func number() throws -> CGFloat {
                guard let n = scanner.number() else { throw ParseError.missingNumber(command: ch, offset: scanner.index) }
                return n
            }
            func point() throws -> CGPoint {
                let x = try number(), y = try number()
                return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
            }
            if upper != UInt8(ascii: "M"), !hasCurrent { throw ParseError.noCurrentPoint(command: ch) }
            var control: CGPoint?
            switch upper {
            case UInt8(ascii: "M"):
                current = try point()
                subpathStart = current
                path.move(to: current)
                hasCurrent = true
            case UInt8(ascii: "L"):
                current = try point()
                path.addLine(to: current)
            case UInt8(ascii: "H"):
                let x = try number()
                current.x = relative ? current.x + x : x
                path.addLine(to: current)
            case UInt8(ascii: "V"):
                let y = try number()
                current.y = relative ? current.y + y : y
                path.addLine(to: current)
            case UInt8(ascii: "C"):
                let c1 = try point(), c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2
                current = end
            case UInt8(ascii: "S"):
                let c1 = reflect(lastControl, about: current, when: [UInt8(ascii: "C"), UInt8(ascii: "S")], last: lastCommand)
                let c2 = try point(), end = try point()
                path.addCurve(to: end, control1: c1, control2: c2)
                control = c2
                current = end
            case UInt8(ascii: "Q"):
                let c = try point(), end = try point()
                path.addQuadCurve(to: end, control: c)
                control = c
                current = end
            case UInt8(ascii: "T"):
                let c = reflect(lastControl, about: current, when: [UInt8(ascii: "Q"), UInt8(ascii: "T")], last: lastCommand)
                let end = try point()
                path.addQuadCurve(to: end, control: c)
                control = c
                current = end
            case UInt8(ascii: "A"):
                let rx = try number(), ry = try number(), rotation = try number()
                guard let large = scanner.flag(), let sweep = scanner.flag() else {
                    throw ParseError.missingNumber(command: ch, offset: scanner.index)
                }
                let end = try point()
                addArc(to: path, from: current, to: end, rx: rx, ry: ry, rotation: rotation, largeArc: large, sweep: sweep)
                current = end
            case UInt8(ascii: "Z"):
                path.closeSubpath()
                current = subpathStart
            default:
                throw ParseError.unexpectedCharacter(ch, offset: scanner.index)
            }
            lastControl = control
            lastCommand = command
            if upper == UInt8(ascii: "Z") { lastCommand = 0 }
        }
        return path
    }

    private static func isCommand(_ c: UInt8) -> Bool {
        "MmLlHhVvCcSsQqTtAaZz".utf8.contains(c)
    }

    private static func reflect(_ control: CGPoint?, about p: CGPoint, when commands: [UInt8], last: UInt8) -> CGPoint {
        let lastUpper = last >= UInt8(ascii: "a") ? last - 32 : last
        guard let control, commands.contains(lastUpper) else { return p }
        return CGPoint(x: 2 * p.x - control.x, y: 2 * p.y - control.y)
    }

    /// SVG elliptical arc (endpoint parameterisation, SVG spec F.6) as cubic Béziers.
    static func addArc(to path: CGMutablePath, from p0: CGPoint, to p1: CGPoint, rx rxIn: CGFloat, ry ryIn: CGFloat,
                       rotation: CGFloat, largeArc: Bool, sweep: Bool) {
        if p0 == p1 { return }
        var rx = abs(rxIn), ry = abs(ryIn)
        if rx == 0 || ry == 0 {
            path.addLine(to: p1)
            return
        }
        let phi = rotation * .pi / 180
        let cosPhi = cos(phi), sinPhi = sin(phi)
        let dx = (p0.x - p1.x) / 2, dy = (p0.y - p1.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy
        // Scale radii up if they cannot span the endpoints.
        let lambda = (x1p * x1p) / (rx * rx) + (y1p * y1p) / (ry * ry)
        if lambda > 1 {
            let s = sqrt(lambda)
            rx *= s; ry *= s
        }
        let num = rx * rx * ry * ry - rx * rx * y1p * y1p - ry * ry * x1p * x1p
        let den = rx * rx * y1p * y1p + ry * ry * x1p * x1p
        var coef = den == 0 ? 0 : sqrt(max(num / den, 0))
        if largeArc == sweep { coef = -coef }
        let cxp = coef * (rx * y1p / ry)
        let cyp = coef * -(ry * x1p / rx)
        let cx = cosPhi * cxp - sinPhi * cyp + (p0.x + p1.x) / 2
        let cy = sinPhi * cxp + cosPhi * cyp + (p0.y + p1.y) / 2
        func angle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
            let a = atan2(ux * vy - uy * vx, ux * vx + uy * vy)
            return a
        }
        let theta1 = angle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = angle((x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep, delta > 0 { delta -= 2 * .pi }
        if sweep, delta < 0 { delta += 2 * .pi }
        // Split into segments of at most 90°, each approximated by one cubic.
        let segments = max(Int(ceil(abs(delta) / (.pi / 2) - 1e-9)), 1)
        let step = delta / CGFloat(segments)
        let k = 4.0 / 3.0 * tan(step / 4)
        func pointOnEllipse(_ t: CGFloat) -> CGPoint {
            CGPoint(x: cx + rx * cos(t) * cosPhi - ry * sin(t) * sinPhi, y: cy + rx * cos(t) * sinPhi + ry * sin(t) * cosPhi)
        }
        func derivative(_ t: CGFloat) -> CGPoint {
            CGPoint(x: -rx * sin(t) * cosPhi - ry * cos(t) * sinPhi, y: -rx * sin(t) * sinPhi + ry * cos(t) * cosPhi)
        }
        var t = theta1
        for i in 0..<segments {
            let t2 = t + step
            let a = pointOnEllipse(t), b = i == segments - 1 ? p1 : pointOnEllipse(t2)
            let da = derivative(t), db = derivative(t2)
            path.addCurve(to: b, control1: CGPoint(x: a.x + k * da.x, y: a.y + k * da.y),
                          control2: CGPoint(x: b.x - k * db.x, y: b.y - k * db.y))
            t = t2
        }
    }

    /// Byte scanner for path data.
    private struct Scanner {
        let bytes: [UInt8]
        var index = 0
        init(_ bytes: [UInt8]) { self.bytes = bytes }

        func peek() -> UInt8? { index < bytes.count ? bytes[index] : nil }
        mutating func advance() { index += 1 }

        /// Skips whitespace and commas; returns false at the end.
        mutating func skipSeparators() -> Bool {
            while let c = peek(), c == 0x20 || c == 0x09 || c == 0x0A || c == 0x0D || c == 0x2C { advance() }
            return peek() != nil
        }

        func peekIsNumberStart() -> Bool {
            guard let c = peek() else { return false }
            return (c >= 0x30 && c <= 0x39) || c == 0x2D || c == 0x2B || c == 0x2E
        }

        /// An arc flag: a single 0 or 1, separators optional.
        mutating func flag() -> Bool? {
            _ = skipSeparators()
            guard let c = peek(), c == 0x30 || c == 0x31 else { return nil }
            advance()
            return c == 0x31
        }

        mutating func number() -> CGFloat? {
            _ = skipSeparators()
            let start = index
            if let c = peek(), c == 0x2D || c == 0x2B { advance() }
            var digits = false, dot = false
            while let c = peek() {
                if c >= 0x30 && c <= 0x39 { digits = true; advance() } else if c == 0x2E && !dot { dot = true; advance() } else { break }
            }
            guard digits else { index = start; return nil }
            if let e = peek(), e == 0x65 || e == 0x45 {
                let save = index
                advance()
                if let s = peek(), s == 0x2D || s == 0x2B { advance() }
                var expDigits = false
                while let c = peek(), c >= 0x30 && c <= 0x39 { expDigits = true; advance() }
                if !expDigits { index = save }
            }
            guard let s = String(bytes: bytes[start..<index], encoding: .ascii), let v = Double(s) else { index = start; return nil }
            return CGFloat(v)
        }
    }
}
