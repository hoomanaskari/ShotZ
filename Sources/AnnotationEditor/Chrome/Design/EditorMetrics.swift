import CoreGraphics
import ShotzUI

/// Editor chrome sizes, all derived from ShotzUI tokens (4/8-pt grid).
enum EditorMetrics {
    /// Options bar: one 28-pt control row with 8 pt above and below.
    static let barHeight: CGFloat = EditorControls.size.hitHeight + 2 * ShotzUI.Space.s
    static let optionHeight: CGFloat = EditorControls.size.hitHeight
    static let toolHeight: CGFloat = ShotzUI.ToolMetrics.size
    static let corner: CGFloat = EditorControls.size.radius
}
