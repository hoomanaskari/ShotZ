import CoreGraphics

/// Modifier keys relevant to tools.
struct ToolModifiers: OptionSet, Sendable {
    let rawValue: Int
    static let shift = ToolModifiers(rawValue: 1 << 0)
    static let option = ToolModifiers(rawValue: 1 << 1)
    static let command = ToolModifiers(rawValue: 1 << 2)
}

/// A mouse event in base-image pixel space.
struct ToolEvent: Sendable {
    var point: CGPoint
    var modifiers: ToolModifiers = []
    var clickCount: Int = 1

    init(_ point: CGPoint, _ modifiers: ToolModifiers = [], clickCount: Int = 1) {
        self.point = point
        self.modifiers = modifiers
        self.clickCount = clickCount
    }
}

/// Keys a tool may want before the canvas handles them.
enum ToolKey: Equatable, Sendable {
    case escape
    case returnKey
    case character(Character)
}

/// Cursor a tool asks for; mapped to `NSCursor` by the canvas.
enum ToolCursor: Equatable, Sendable {
    case arrow, crosshair, iBeam, move, pointingHand, resize(angle: CGFloat)
}

/// A canvas tool. Tools only talk to `EditorModel` (and through it `DocumentStore`).
@MainActor protocol Tool: AnyObject {
    var kind: ToolKind { get }
    func mouseDown(_ event: ToolEvent)
    func mouseDragged(_ event: ToolEvent)
    func mouseUp(_ event: ToolEvent)
    /// Return true when handled.
    func keyDown(_ key: ToolKey) -> Bool
    func cursor(at point: CGPoint, modifiers: ToolModifiers) -> ToolCursor
    func activate()
    func deactivate()
}

extension Tool {
    func keyDown(_ key: ToolKey) -> Bool { false }
    func activate() {}
    func deactivate() {}
}
