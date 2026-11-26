import CoreGraphics

/// Highlighter marks are drawn with multiply blending.
public enum HighlightGeometry: Codable, Sendable, Equatable, Hashable {
    /// Smoothed marker stroke; width from `ObjectStyle.lineWidth`.
    case freehand([CGPoint])
    case rect(CGRect)
}
