import AppKit
import ShotzCore

/// ShotZ's design system: tokens (spacing, radii, type, semantic colours,
/// state styles, timings) and the shared controls every surface uses.
/// Owned by one engineer; other modules consume it and keep no bespoke
/// button or control styling. See docs/ARCHITECTURE.md.
public enum ShotzUI {}

extension ShotzUI {
    /// True when `appearance` resolves to a dark appearance (including increased-contrast dark).
    public static func isDark(in appearance: NSAppearance) -> Bool { Palette.variant(appearance).isDark }

    /// True when increased contrast applies (system setting, or `Palette.increasedContrastOverride`).
    public static func isIncreasedContrast(in appearance: NSAppearance) -> Bool { Palette.variant(appearance).isHighContrast }
}
