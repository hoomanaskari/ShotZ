import AppKit
import CoreGraphics

/// Gradient end points in a top-left unit square. 0° = left→right, 90° = top→bottom.
enum GradientGeometry {
    static func points(angle degrees: CGFloat) -> (CGPoint, CGPoint) {
        let a = degrees * .pi / 180
        let dx = cos(a) / 2, dy = sin(a) / 2
        return (CGPoint(x: 0.5 - dx, y: 0.5 - dy), CGPoint(x: 0.5 + dx, y: 0.5 + dy))
    }
}

/// Content bounds of images with transparent margins (window captures).
enum OpaqueBounds {
    /// nil when the image has no alpha or its corners are opaque (not a window capture).
    static func compute(_ image: CGImage) -> CGRect? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        // Sample a small copy: cheap even for 5K images.
        let maxSide = 256
        let scale = min(1, CGFloat(maxSide) / CGFloat(max(image.width, image.height)))
        let w = max(Int(CGFloat(image.width) * scale), 1), h = max(Int(CGFloat(image.height) * scale), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                  space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let alpha = data.bindMemory(to: UInt8.self, capacity: w * h)
        // Row 0 of the buffer is the top of the image.
        func a(_ x: Int, _ y: Int) -> UInt8 { alpha[y * w + x] }
        let corners = [a(0, 0), a(w - 1, 0), a(0, h - 1), a(w - 1, h - 1)]
        guard corners.allSatisfy({ $0 < 8 }) else { return nil }
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where a(x, y) > 128 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }
        let inv = 1 / scale
        return CGRect(x: CGFloat(minX) * inv, y: CGFloat(minY) * inv,
                      width: CGFloat(maxX - minX + 1) * inv, height: CGFloat(maxY - minY + 1) * inv)
    }
}

@MainActor enum CursorMapping {
    static func cursor(for c: ToolCursor) -> NSCursor {
        switch c {
        case .arrow: return NSCursor.arrow
        case .crosshair: return NSCursor.crosshair
        case .iBeam: return NSCursor.iBeam
        case .move: return NSCursor.openHand
        case .pointingHand: return NSCursor.pointingHand
        case .resize(let angle):
            // Angle from the object's centre to the handle (y down).
            let deg = (angle * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
            let position: NSCursor.FrameResizePosition = switch deg {
            case 337.5..., ..<22.5: .right
            case 22.5..<67.5: .bottomRight
            case 67.5..<112.5: .bottom
            case 112.5..<157.5: .bottomLeft
            case 157.5..<202.5: .left
            case 202.5..<247.5: .topLeft
            case 247.5..<292.5: .top
            default: .topRight
            }
            return NSCursor.frameResize(position: position, directions: .all)
        }
    }
}
