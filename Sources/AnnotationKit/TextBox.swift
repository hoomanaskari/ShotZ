import CoreGraphics

/// Font size comes from `ObjectStyle.fontSize`; colour from `ObjectStyle.color`.
public struct TextBox: Codable, Sendable, Equatable, Hashable {
    /// Top-left of the text box.
    public var origin: CGPoint
    /// nil = grows with the text, no wrapping.
    public var wrapWidth: CGFloat?
    public var string: String
    public var style: TextStyle

    public init(origin: CGPoint, wrapWidth: CGFloat? = nil, string: String, style: TextStyle = TextStyle()) {
        self.origin = origin
        self.wrapWidth = wrapWidth
        self.string = string
        self.style = style
    }
}
