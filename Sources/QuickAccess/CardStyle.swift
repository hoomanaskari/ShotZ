import AppKit
import ShotzCore
import ShotzUI

/// How each card size maps onto ShotzUI (DESIGN.md, `StackCardHover`): control
/// sizes and the corner inset. Every colour, radius, font and timing comes
/// from ShotzUI tokens.
struct CardStyle {
    /// Card corner radius (`StackCardHover.cornerRadius`, `Radius.card`).
    let cornerRadius: CGFloat = ShotzUI.Radius.card
    /// Round corner buttons (Close, Annotate, Quick Look).
    let cornerSize: ShotzUI.ControlSize
    /// Copy / Save pair and the caption pill.
    let pillSize: ShotzUI.ControlSize
    /// Inset of a corner button's hit frame from the card edge. Chosen so the
    /// glass chrome lands `Space.s` (8 pt) in, except on Small cards where the
    /// card is too short for three 28-pt rows and the chrome sits 6 pt in.
    let hitInset: CGFloat

    init(size: CardSize) {
        switch size {
        case .small:
            cornerSize = .compact; pillSize = .compact
            hitInset = 4
        case .medium:
            cornerSize = .regular; pillSize = .regular
            hitInset = ShotzUI.Space.s
        case .large:
            cornerSize = .regular; pillSize = .regular
            hitInset = ShotzUI.Space.s
        }
    }

    /// The image dims by 25 % under the controls (`StackCardHover`).
    static let scrimOpacity: CGFloat = 0.25

    // MARK: Colours (resolved against an appearance, all from ShotzUI.Palette)

    struct Palette {
        let backdrop: CGColor
        /// Over the blurred letterbox backdrop, so it reads as background.
        let backdropTint: CGColor
        let border: CGColor
        let shadow: ShotzUI.Elevation
    }

    @MainActor static func palette(for appearance: NSAppearance) -> Palette {
        let P = ShotzUI.Palette.self
        let dark = appearance.bestMatch(from: [.darkAqua, .aqua, .accessibilityHighContrastDarkAqua, .accessibilityHighContrastAqua]).map { $0 == .darkAqua || $0 == .accessibilityHighContrastDarkAqua } ?? false
        let surface = P.surface.resolved(in: appearance)
        // Cards float over arbitrary wallpaper, so they keep the overlay shadow
        // in dark too (ShotzUI's dark rule assumes a known surface beneath).
        var shadow = ShotzUI.Elevation.overlay
        if dark { shadow.opacity = min(1, shadow.opacity * 2.5) }
        return Palette(
            backdrop: P.surfaceSunken.composited(over: surface).cgColor,
            backdropTint: surface.withAlphaComponent(dark ? 0.5 : 0.42).cgColor,
            border: P.border.resolved(in: appearance).cgColor,
            shadow: shadow
        )
    }
}
