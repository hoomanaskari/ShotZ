import AppKit
import CoreGraphics

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
