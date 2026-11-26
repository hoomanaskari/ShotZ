import AppKit
import ShotzCore
import ShotzUI

/// How each card size maps onto ShotzUI (`ShotzUI.CardSize`, `StackCardHover`).
/// Every metric, colour, radius, font and timing comes from ShotzUI.
struct CardStyle {
    let ui: ShotzUI.CardSize
    /// Card corner radius (`CardSize.cornerRadius`: 8 small, 10 otherwise).
    var cornerRadius: CGFloat { ui.cornerRadius }
    /// Copy/Save carry labels (the stack's per-size rule: icon-only on Small).
    let labelledPair: Bool
    /// The pixel-size caption pill (Small shows the size in the card's
    /// tooltip and context menu instead).
    let showsCaption: Bool
    /// Confirmation pill size.
    var compactToast: Bool { ui != .large }

    /// Smallest visible gap between any two controls, or a control and the card edge.
    static let minimumGap: CGFloat = 6

    init(size: CardSize) {
        ui = ShotzUI.CardSize(rawValue: size.rawValue) ?? .large
        labelledPair = ui != .small
        showsCaption = ui != .small
    }

    // MARK: Colours (resolved against an appearance, all from ShotzUI.Palette)

    struct Palette {
        let backdrop: CGColor
        /// Over the blurred letterbox backdrop, so it reads as background.
        let backdropTint: CGColor
        let border: CGColor
        /// Dims the image under the hover controls (`Palette.scrim`).
        let scrim: CGColor
        let shadow: ShotzUI.Elevation
    }

    @MainActor static func palette(for appearance: NSAppearance) -> Palette {
        let P = ShotzUI.Palette.self
        let dark = ShotzUI.isDark(in: appearance)
        let surface = P.surface.resolved(in: appearance)
        return Palette(
            backdrop: P.surfaceSunken.composited(over: surface).cgColor,
            backdropTint: surface.withAlphaComponent(dark ? 0.5 : 0.42).cgColor,
            border: P.border.resolved(in: appearance).cgColor,
            scrim: P.scrim.resolved(in: appearance).cgColor,
            // Cards float over arbitrary wallpaper.
            shadow: .floating(dark: dark)
        )
    }
}
