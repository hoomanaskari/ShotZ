import CoreGraphics
import ShotzCore

/// Pure geometry of one display's stack (SPEC §4.1). Screen coordinates are
/// AppKit's (bottom-left origin); card frames are in panel coordinates.
///
/// The panel is a fixed column hugging the stack's edge of the visible frame,
/// tall enough for `capacity` cards. Slot 0 is the newest card, at the bottom.
struct StackLayout: Equatable {
    static let inset: CGFloat = 16
    static let spacing: CGFloat = 10
    static let maxVisible = 5
    /// Room around cards for their shadow, on the sides away from the edge.
    static let shadowMargin: CGFloat = 16

    var visibleFrame: CGRect
    var side: StackSide
    var cardSize: CGSize

    init(visibleFrame: CGRect, side: StackSide, cardSize: CGSize) {
        self.visibleFrame = visibleFrame
        self.side = side
        // Whole points keep edges crisp (16:10 of 250 is 156.25).
        self.cardSize = CGSize(width: cardSize.width.rounded(), height: cardSize.height.rounded())
    }

    /// How many cards fit (1…maxVisible).
    var capacity: Int {
        let usable = visibleFrame.height - Self.inset - Self.shadowMargin + Self.spacing
        let fit = Int((usable / (cardSize.height + Self.spacing)).rounded(.down))
        return min(Self.maxVisible, max(1, fit))
    }

    var panelFrame: CGRect {
        let width = Self.inset + cardSize.width + Self.shadowMargin
        let n = CGFloat(capacity)
        let height = Self.inset + n * cardSize.height + (n - 1) * Self.spacing + Self.shadowMargin
        let x = side == .left ? visibleFrame.minX : visibleFrame.maxX - width
        return CGRect(x: x.rounded(), y: visibleFrame.minY.rounded(), width: width, height: height)
    }

    /// Frame of the card in `slot` (0 = newest, bottom), panel coordinates.
    func cardFrame(slot: Int) -> CGRect {
        let x = side == .left ? Self.inset : Self.shadowMargin
        let y = Self.inset + CGFloat(slot) * (cardSize.height + Self.spacing)
        return CGRect(origin: CGPoint(x: x, y: y), size: cardSize)
    }

    /// Where a card starts its entrance: just past the screen edge, same row.
    func entranceFrame(slot: Int) -> CGRect {
        offEdge(cardFrame(slot: slot))
    }

    /// `frame` moved horizontally until it is fully past the screen edge.
    func offEdge(_ frame: CGRect) -> CGRect {
        var f = frame
        switch side {
        case .left: f.origin.x = -(cardSize.width + 4)
        case .right: f.origin.x = panelFrame.width + 4
        }
        return f
    }

    /// Slots for `count` cards ordered newest first: the visible ones get
    /// 0..<capacity, the rest nil (kept, but hidden until room returns).
    func slots(count: Int) -> [Int?] {
        (0..<count).map { $0 < capacity ? $0 : nil }
    }

    /// True when a screen point is at (or past) the stack's own screen edge,
    /// which is where a swipe-away drag ends.
    func isAtEdge(_ point: CGPoint, screenFrame: CGRect, tolerance: CGFloat = 4) -> Bool {
        guard point.y >= screenFrame.minY - 1, point.y <= screenFrame.maxY + 1 else { return false }
        switch side {
        case .left: return point.x <= screenFrame.minX + tolerance && point.x >= screenFrame.minX - 60
        case .right: return point.x >= screenFrame.maxX - tolerance && point.x <= screenFrame.maxX + 60
        }
    }
}
