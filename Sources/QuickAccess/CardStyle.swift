import AppKit
import ShotzCore

/// Shotz's own card look: metrics per size, colours per appearance.
struct CardStyle {
    let cornerRadius: CGFloat
    /// Round icon button diameter and its inset from the card edge.
    let chip: CGFloat
    let chipInset: CGFloat
    let chipIconSize: CGFloat
    let pillHeight: CGFloat
    let pillIconSize: CGFloat
    let pillGap: CGFloat
    let pillFont: NSFont
    let captionFont: NSFont
    let captionHeight: CGFloat

    init(size: CardSize) {
        switch size {
        case .small:
            // Visible controls are smaller here; hit frames still reach 28 pt.
            cornerRadius = 10; chip = 22; chipInset = 6; chipIconSize = 12
            pillHeight = 22; pillIconSize = 12; pillGap = 5
            pillFont = .systemFont(ofSize: 10.5, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 9, weight: .semibold)
            captionHeight = 17
        case .medium:
            cornerRadius = 10; chip = 28; chipInset = 7; chipIconSize = 14
            pillHeight = 28; pillIconSize = 14; pillGap = 8
            pillFont = .systemFont(ofSize: 12, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
            captionHeight = 20
        case .large:
            cornerRadius = 11; chip = 30; chipInset = 8; chipIconSize = 15
            pillHeight = 30; pillIconSize = 15; pillGap = 8
            pillFont = .systemFont(ofSize: 12.5, weight: .semibold)
            captionFont = .monospacedDigitSystemFont(ofSize: 10.5, weight: .semibold)
            captionHeight = 22
        }
    }

    // MARK: Colours (resolved against an appearance)

    struct Palette {
        let backdrop: CGColor
        /// Over the blurred backdrop, so it reads as background, not content.
        let backdropTint: CGColor
        let border: CGColor
        /// Large soft shadow and tight contact shadow.
        let ambientShadowOpacity: Float
        let contactShadowOpacity: Float
        /// Hover scrim: edges darker than the middle so corner controls read.
        let scrimEdge: CGColor
        let scrimMiddle: CGColor
        let accentInk: NSColor
        let failureInk: NSColor
    }

    static func palette(for appearance: NSAppearance) -> Palette {
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        if dark {
            return Palette(
                backdrop: CGColor(srgbRed: 0.15, green: 0.15, blue: 0.17, alpha: 1),
                backdropTint: CGColor(srgbRed: 0.07, green: 0.07, blue: 0.09, alpha: 0.5),
                border: CGColor(gray: 1, alpha: 0.14),
                ambientShadowOpacity: 0.5,
                contactShadowOpacity: 0.5,
                scrimEdge: CGColor(gray: 0, alpha: 0.42),
                scrimMiddle: CGColor(gray: 0, alpha: 0.14),
                accentInk: NSColor(srgbRed: 0.40, green: 0.84, blue: 0.52, alpha: 1),
                failureInk: NSColor(srgbRed: 1, green: 0.52, blue: 0.44, alpha: 1)
            )
        }
        return Palette(
            backdrop: CGColor(srgbRed: 0.92, green: 0.92, blue: 0.94, alpha: 1),
            backdropTint: CGColor(gray: 0.97, alpha: 0.42),
            border: CGColor(gray: 0, alpha: 0.12),
            ambientShadowOpacity: 0.22,
            contactShadowOpacity: 0.18,
            scrimEdge: CGColor(gray: 0, alpha: 0.30),
            scrimMiddle: CGColor(gray: 0, alpha: 0.08),
            accentInk: NSColor(srgbRed: 0.12, green: 0.6, blue: 0.3, alpha: 1),
            failureInk: NSColor(srgbRed: 0.85, green: 0.25, blue: 0.18, alpha: 1)
        )
    }
}
