import CoreGraphics

/// One filled shape of an icon. Most icons have a single opaque layer; glyphs that show a
/// translucent fill (e.g. "outline with translucent fill") add layers with opacity < 1.
public struct IconLayer: @unchecked Sendable {
    // @unchecked: CGPath is immutable once built and safe to share across threads.
    /// Filled with the non-zero winding rule.
    public let path: CGPath
    public let opacity: CGFloat

    public init(path: CGPath, opacity: CGFloat = 1) {
        self.path = path
        self.opacity = opacity
    }
}
