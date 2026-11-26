import AppKit

extension ShotzUI {
    /// Animation timings. Durations collapse to 0 when Reduce Motion is on.
    @MainActor public enum Motion {
        /// 0.12 s: hover and press feedback, chip toggles.
        public static var fast: TimeInterval { reduced ? 0 : 0.12 }
        /// 0.2 s: segmented selection slide, popover content changes.
        public static var standard: TimeInterval { reduced ? 0 : 0.2 }
        /// 0.3 s: panels and toasts appearing.
        public static var slow: TimeInterval { reduced ? 0 : 0.3 }
        /// Ease-out for things arriving, ease-in-out for things moving.
        public static var arrive: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.2, 0.8, 0.2, 1) }
        public static var move: CAMediaTimingFunction { CAMediaTimingFunction(controlPoints: 0.4, 0, 0.2, 1) }

        public static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
        /// When true, glass and translucent materials become solid.
        public static var reduceTransparency: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency }
    }

    /// Shadows (light appearance; dark relies on borders and surface steps instead).
    public struct Elevation: Sendable {
        public var offsetY: CGFloat
        public var blur: CGFloat
        public var opacity: CGFloat

        /// Raised controls (secondary buttons, segment thumb).
        public static let control = Elevation(offsetY: 0.5, blur: 1.5, opacity: 0.10)
        /// Cards in Settings.
        public static let card = Elevation(offsetY: 1, blur: 3, opacity: 0.06)
        /// Popovers, panels, toasts.
        public static let overlay = Elevation(offsetY: 6, blur: 18, opacity: 0.18)
    }
}
