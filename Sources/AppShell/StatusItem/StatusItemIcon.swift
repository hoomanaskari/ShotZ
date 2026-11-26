import AppKit
import ShotzCore

/// ShotZ's menu-bar glyph. Without an owner-supplied master
/// (`scripts/make-icons.sh --glyph`), it is drawn in code: four capture
/// corners around a lens ("corners + lens", `MenuBarGlyphGeometry`).
/// Production is a template image (menu-bar colour); ShotZ Dev is tinted
/// amber, matching the DEV band on its app icon, so the two are never
/// confused side by side.
enum StatusItemIcon {
    /// The amber of Shotz Dev's glyph and icon band.
    static let devTint = NSColor(srgbRed: 1.0, green: 0.62, blue: 0.04, alpha: 1)

    static func make(variant: AppVariant = .production) -> NSImage {
        if let art = suppliedGlyph() {
            return variant == .development ? tinted(art, devTint, name: variant.displayName) : named(art, variant.displayName)
        }
        return drawn(variant: variant)
    }

    /// The owner's glyph from `scripts/make-icons.sh --glyph`, as a template image (nil when none was supplied).
    static func suppliedGlyph() -> NSImage? {
        guard let one = MenuBarGlyphArt.png1x.flatMap({ Data(base64Encoded: $0) }).flatMap(NSBitmapImageRep.init(data:)) else {
            return nil
        }
        let image = NSImage(size: NSSize(width: 18, height: 18))
        one.size = image.size
        image.addRepresentation(one)
        if let two = MenuBarGlyphArt.png2x.flatMap({ Data(base64Encoded: $0) }).flatMap(NSBitmapImageRep.init(data:)) {
            two.size = image.size
            image.addRepresentation(two)
        }
        image.isTemplate = true
        return image
    }

    private static func named(_ image: NSImage, _ name: String) -> NSImage {
        image.accessibilityDescription = name
        return image
    }

    /// The template glyph filled with `color` (not a template: keeps its colour in the menu bar).
    private static func tinted(_ template: NSImage, _ color: NSColor, name: String) -> NSImage {
        let image = NSImage(size: template.size, flipped: false) { rect in
            template.draw(in: rect)
            color.setFill()
            rect.fill(using: .sourceIn)
            return true
        }
        image.isTemplate = false
        image.accessibilityDescription = name
        return image
    }

    /// The status item's point size (the 18-pt menu-bar canvas; layout unchanged).
    static let pointSize = 18

    /// The drawn glyph, "corners + lens" (`MenuBarGlyphGeometry`): a template
    /// image in production, amber and non-template in ShotZ Dev, with a
    /// pixel-snapped bitmap for each backing scale.
    static func drawn(variant: AppVariant) -> NSImage {
        let ink: CGColor = variant == .development ? devTint.cgColor : CGColor(gray: 0, alpha: 1)
        let image = MenuBarGlyphGeometry.image(pointSize: pointSize, ink: ink)
        image.isTemplate = variant == .production
        image.accessibilityDescription = variant.displayName
        return image
    }
}
