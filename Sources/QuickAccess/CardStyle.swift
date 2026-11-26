import AppKit
import ShotzCore

/// Shotz's own card look: metrics per size, colours per appearance.
struct CardStyle {
    let cornerRadius: CGFloat = 10
    /// Corner chip diameter and its inset from the card edge.
    let chip: CGFloat
    let chipInset: CGFloat
    let pillHeight: CGFloat
    let pillFont: NSFont
    let captionFont: NSFont
    let symbolPointSize: CGFloat

    init(size: CardSize) {
        switch size {
        case .small:
            chip = 22; chipInset = 6; pillHeight = 24
            pillFont = .systemFont(ofSize: 11, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 9.5, weight: .medium)
            symbolPointSize = 10
        case .medium:
            chip = 24; chipInset = 7; pillHeight = 26
            pillFont = .systemFont(ofSize: 12, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 10, weight: .medium)
            symbolPointSize = 11
        case .large:
            chip = 26; chipInset = 8; pillHeight = 28
            pillFont = .systemFont(ofSize: 12.5, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
            symbolPointSize = 12
        }
    }

    // MARK: Colours (resolved against an appearance)

    struct Palette {
        let backdrop: CGColor
        let border: CGColor
        let shadowOpacity: Float
        let dim: CGColor
        let chipFill: CGColor
        let chipPressed: CGColor
        let chipStroke: CGColor
        let chipInk: NSColor
        let accentInk: NSColor
        let failureInk: NSColor
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return Palette(
                backdrop: CGColor(srgbRed: 0.16, green: 0.16, blue: 0.18, alpha: 1),
                border: CGColor(gray: 1, alpha: 0.16),
                shadowOpacity: 0.55,
                dim: CGColor(gray: 0, alpha: 0.34),
                chipFill: CGColor(srgbRed: 0.11, green: 0.11, blue: 0.12, alpha: 0.88),
                chipPressed: CGColor(srgbRed: 0.24, green: 0.24, blue: 0.26, alpha: 0.95),
                chipStroke: CGColor(gray: 1, alpha: 0.12),
                chipInk: .white,
                accentInk: NSColor(srgbRed: 0.45, green: 0.85, blue: 0.55, alpha: 1),
                failureInk: NSColor(srgbRed: 1, green: 0.5, blue: 0.45, alpha: 1)
            )
        }
        return Palette(
            backdrop: CGColor(srgbRed: 0.91, green: 0.91, blue: 0.93, alpha: 1),
            border: CGColor(gray: 0, alpha: 0.14),
            shadowOpacity: 0.24,
            dim: CGColor(gray: 0, alpha: 0.26),
            chipFill: CGColor(gray: 1, alpha: 0.94),
            chipPressed: CGColor(gray: 0.84, alpha: 0.96),
            chipStroke: CGColor(gray: 0, alpha: 0.08),
            chipInk: NSColor(white: 0.1, alpha: 1),
            accentInk: NSColor(srgbRed: 0.1, green: 0.55, blue: 0.25, alpha: 1),
            failureInk: NSColor(srgbRed: 0.8, green: 0.2, blue: 0.15, alpha: 1)
        )
    }
}
