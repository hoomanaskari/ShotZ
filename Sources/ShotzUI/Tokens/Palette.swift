import AppKit
import Synchronization

extension ShotzUI {
    /// Semantic colours. Each resolves for light, dark and both increased-contrast appearances;
    /// accent-derived colours follow the user's system accent colour.
    public enum Palette {
        // MARK: Surfaces
        /// Window background (Settings, editor chrome).
        public static var windowBackground: NSColor { dynamic("windowBackground", hex(0xF4F4F6), hex(0x1C1C1F), hex(0xFFFFFF), hex(0x000000)) }
        /// Raised containers: grouped cards, popovers, side panels.
        public static var surface: NSColor { dynamic("surface", hex(0xFFFFFF), hex(0x26262A), hex(0xFFFFFF), hex(0x141416)) }
        /// Recessed areas: options bar, segmented track, slider track.
        public static var surfaceSunken: NSColor { dynamic("surfaceSunken", black(0.05), white(0.06), black(0.08), white(0.12)) }
        /// The lifted element inside a sunken track (segment thumb, secondary button).
        public static var raised: NSColor { dynamic("raised", hex(0xFFFFFF), hex(0x4A4A50), hex(0xFFFFFF), hex(0x3A3A40)) }

        // MARK: Lines
        public static var separator: NSColor { dynamic("separator", black(0.10), white(0.10), black(0.40), white(0.45)) }
        /// Edge of colour swatches: strong enough that black on dark and white on light stay visible.
        public static var swatchEdge: NSColor { dynamic("swatchEdge", black(0.16), white(0.30), black(0.5), white(0.6)) }
        /// Hairline around raised controls so they hold their edge on any background.
        public static var border: NSColor { dynamic("border", black(0.12), white(0.08), black(0.55), white(0.60)) }

        // MARK: Text and glyphs
        public static var textPrimary: NSColor { dynamic("textPrimary", black(0.88), white(0.92), black(1), white(1)) }
        public static var textSecondary: NSColor { dynamic("textSecondary", black(0.58), white(0.64), black(0.80), white(0.84)) }
        /// Placeholders and disabled content only (not for text that must be read).
        public static var textTertiary: NSColor { dynamic("textTertiary", black(0.36), white(0.38), black(0.60), white(0.62)) }

        // MARK: Interaction fills (neutral)
        public static var fillHover: NSColor { dynamic("fillHover", black(0.06), white(0.08), black(0.10), white(0.16)) }
        public static var fillPressed: NSColor { dynamic("fillPressed", black(0.11), white(0.13), black(0.18), white(0.24)) }

        // MARK: Accent family (follows the system accent)
        /// Primary button fill: the accent, deepened just enough (more in light mode) that its
        /// label reaches 4.5:1 whatever accent the user picked.
        public static var accentFill: NSColor {
            NSColor(name: "accentFill") { a in accentFillColor(accent: systemAccent(in: a), variant: variant(a)) }
        }
        /// Label/glyph colour on `accentFill`: white or near-black, whichever contrasts more.
        public static var onAccent: NSColor {
            NSColor(name: "onAccent") { a in bestLabel(on: accentFillColor(accent: systemAccent(in: a), variant: variant(a))) }
        }
        /// Tint behind a selected tool or active chip.
        public static var selectedFill: NSColor {
            NSColor(name: "selectedFill") { a in selectedFillColor(accent: systemAccent(in: a), variant: variant(a)) }
        }
        /// Glyph and label colour on `selectedFill`: the accent, deepened (light) or lightened (dark)
        /// until it reads at 4.5:1 (7:1 with increased contrast) on the tint over any surface.
        public static var selectedContent: NSColor {
            NSColor(name: "selectedContent") { a in
                let v = variant(a), accent = systemAccent(in: a)
                let tint = selectedFillColor(accent: accent, variant: v)
                let backs = [windowBackground, surface].map { tint.composited(over: $0.resolved(in: a)) }
                let start = v.isDark ? accent.mixed(with: .white, 0.25) : accent.mixed(with: .black, 0.18)
                return ensuring(start, contrast: v.isHighContrast ? 7 : 4.6, against: backs, toward: v.isDark ? .white : .black)
            }
        }
        /// Thin inner edge of selected states, so the tint has a crisp boundary.
        public static var selectedBorder: NSColor {
            NSColor(name: "selectedBorder") { a in systemAccent(in: a).withAlphaComponent(variant(a).isHighContrast ? 0.7 : 0.30) }
        }
        public static var focusRing: NSColor {
            NSColor(name: "focusRing") { a in
                let v = variant(a)
                return systemAccent(in: a).withAlphaComponent(v.isHighContrast ? 0.9 : (v.isDark ? 0.75 : 0.5))
            }
        }

        // MARK: Status
        public static var danger: NSColor { dynamic("danger", hex(0xC4302B), hex(0xFFA5A0), hex(0x9E1B17), hex(0xFFC8C4)) }
        public static var success: NSColor { dynamic("success", hex(0x1A7F45), hex(0x4CD98E), hex(0x0E5C30), hex(0x7BEAB0)) }
        public static var warning: NSColor { dynamic("warning", hex(0x9A6100), hex(0xFFC453), hex(0x6E4500), hex(0xFFD88A)) }

        // MARK: Glass (over images: stack hover buttons)
        /// Background of controls floating over arbitrary image content.
        public static var glassFill: NSColor { dynamic("glassFill", hex(0x1A1A1D, 0.62), hex(0x1A1A1D, 0.62), hex(0x000000, 0.85), hex(0x000000, 0.85)) }
        public static var glassFillHover: NSColor { dynamic("glassFillHover", hex(0x1A1A1D, 0.78), hex(0x1A1A1D, 0.78), hex(0x000000, 0.95), hex(0x000000, 0.95)) }
        public static var glassContent: NSColor { .white }

        // MARK: Building blocks

        enum Variant {
            case light, dark, lightHC, darkHC
            var isHighContrast: Bool { self == .lightHC || self == .darkHC }
            var isDark: Bool { self == .dark || self == .darkHC }
        }

        /// Forces the increased-contrast palette (galleries and tests: `NSAppearance(named:)` cannot
        /// create the high-contrast appearances; in the app macOS applies them itself).
        public static var increasedContrastOverride: Bool {
            get { increasedContrastStorage.withLock { $0 } }
            set { increasedContrastStorage.withLock { $0 = newValue } }
        }
        private static let increasedContrastStorage = Mutex(false)

        static func variant(_ a: NSAppearance) -> Variant {
            let v: Variant = switch a.bestMatch(from: [.aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua]) {
            case .darkAqua: .dark
            case .accessibilityHighContrastAqua: .lightHC
            case .accessibilityHighContrastDarkAqua: .darkHC
            default: .light
            }
            guard increasedContrastOverride else { return v }
            return v.isDark ? .darkHC : .lightHC
        }

        static func dynamic(_ name: String, _ light: NSColor, _ dark: NSColor, _ lightHC: NSColor, _ darkHC: NSColor) -> NSColor {
            NSColor(name: NSColor.Name("ShotZ." + name)) { a in
                switch variant(a) {
                case .light: light
                case .dark: dark
                case .lightHC: lightHC
                case .darkHC: darkHC
                }
            }
        }

        /// Replaces the system accent (previews, galleries and golden tests only).
        public static var accentOverride: NSColor? {
            get { accentOverrideStorage.withLock { $0 } }
            set { accentOverrideStorage.withLock { $0 = newValue } }
        }
        private static let accentOverrideStorage = Mutex<NSColor?>(nil)

        /// The system accent resolved for an appearance, in sRGB.
        static func systemAccent(in a: NSAppearance) -> NSColor {
            if let o = accentOverride { return o.usingColorSpace(.sRGB) ?? o }
            var c = NSColor.controlAccentColor
            a.performAsCurrentDrawingAppearance { c = NSColor.controlAccentColor.usingColorSpace(.sRGB) ?? hex(0x0A84FF) }
            return c
        }

        static func hex(_ v: UInt32, _ alpha: CGFloat = 1) -> NSColor {
            NSColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255, green: CGFloat((v >> 8) & 0xFF) / 255, blue: CGFloat(v & 0xFF) / 255, alpha: alpha)
        }
        static func black(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 0, green: 0, blue: 0, alpha: a) }
        static func white(_ a: CGFloat) -> NSColor { NSColor(srgbRed: 1, green: 1, blue: 1, alpha: a) }

        static func accentFillColor(accent: NSColor, variant v: Variant) -> NSColor {
            let start: CGFloat = v == .light ? 0.12 : v == .lightHC ? 0.30 : v == .dark ? 0 : 0.15
            let goal: CGFloat = v.isHighContrast ? 7 : 4.6
            var t = start
            while t < 0.9 {
                let c = accent.mixed(with: .black, t)
                if max(contrast(.white, c), contrast(nearBlack, c)) >= goal { return c }
                t += 0.03
            }
            return accent.mixed(with: .black, 0.9)
        }

        static func selectedFillColor(accent: NSColor, variant v: Variant) -> NSColor {
            accent.withAlphaComponent(v == .light ? 0.14 : v == .lightHC ? 0.22 : v == .dark ? 0.26 : 0.36)
        }

        static let nearBlack = NSColor(srgbRed: 0.067, green: 0.067, blue: 0.075, alpha: 1)

        static func bestLabel(on fill: NSColor) -> NSColor {
            contrast(.white, fill) >= contrast(nearBlack, fill) ? .white : nearBlack
        }

        /// `color` moved toward `target` in small steps until it meets `minimum` against every background.
        static func ensuring(_ color: NSColor, contrast minimum: CGFloat, against backgrounds: [NSColor], toward target: NSColor) -> NSColor {
            for step in 0...40 {
                let c = color.mixed(with: target, CGFloat(step) * 0.025)
                if backgrounds.allSatisfy({ contrast(c, $0) >= minimum }) { return c }
            }
            return target
        }

        // MARK: Contrast maths (WCAG 2)

        /// Relative luminance of an opaque sRGB colour.
        public static func luminance(_ c: NSColor) -> CGFloat {
            let s = c.usingColorSpace(.sRGB) ?? c
            func lin(_ v: CGFloat) -> CGFloat { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * lin(s.redComponent) + 0.7152 * lin(s.greenComponent) + 0.0722 * lin(s.blueComponent)
        }

        /// Contrast ratio between two opaque colours (1…21).
        public static func contrast(_ a: NSColor, _ b: NSColor) -> CGFloat {
            let la = luminance(a), lb = luminance(b)
            return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
        }
    }
}

extension NSColor {
    /// This colour resolved for `appearance`, in sRGB.
    public func resolved(in appearance: NSAppearance) -> NSColor {
        var out = self
        appearance.performAsCurrentDrawingAppearance { out = self.usingColorSpace(.sRGB) ?? self }
        return out
    }

    /// `self` composited over an opaque `background` (for contrast checks).
    public func composited(over background: NSColor) -> NSColor {
        let f = usingColorSpace(.sRGB) ?? self, b = background.usingColorSpace(.sRGB) ?? background
        let a = f.alphaComponent
        return NSColor(srgbRed: f.redComponent * a + b.redComponent * (1 - a), green: f.greenComponent * a + b.greenComponent * (1 - a),
                       blue: f.blueComponent * a + b.blueComponent * (1 - a), alpha: 1)
    }

    func mixed(with other: NSColor, _ t: CGFloat) -> NSColor {
        let a = usingColorSpace(.sRGB) ?? self, b = other.usingColorSpace(.sRGB) ?? other
        return NSColor(srgbRed: a.redComponent + (b.redComponent - a.redComponent) * t, green: a.greenComponent + (b.greenComponent - a.greenComponent) * t,
                       blue: a.blueComponent + (b.blueComponent - a.blueComponent) * t, alpha: a.alphaComponent)
    }
}
