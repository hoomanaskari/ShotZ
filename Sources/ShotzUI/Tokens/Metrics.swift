import AppKit

extension ShotzUI {
    /// Spacing scale on a 4/8-pt grid. Use these, never literals, for gaps and insets.
    public enum Space {
        /// 2 pt: hairline nudges (icon-to-badge).
        public static let xxs: CGFloat = 2
        /// 4 pt: icon-to-label inside a control, swatch gaps.
        public static let xs: CGFloat = 4
        /// 8 pt: between controls in a group, control horizontal padding (compact).
        public static let s: CGFloat = 8
        /// 12 pt: between groups (with a separator), row vertical padding.
        public static let m: CGFloat = 12
        /// 16 pt: card insets, settings row horizontal inset.
        public static let l: CGFloat = 16
        /// 24 pt: between sections.
        public static let xl: CGFloat = 24
        /// 32 pt: window margins in Settings and onboarding.
        public static let xxl: CGFloat = 32
    }

    /// Corner radii. Controls use `ControlSize.radius`; containers use these.
    public enum Radius {
        /// Swatch cells, key caps, small badges.
        public static let small: CGFloat = 4
        /// Grouped cards, banners, menus.
        public static let card: CGFloat = 10
        /// Popovers, side panels, toasts that aren't capsules.
        public static let panel: CGFloat = 12
    }

    /// The three control heights. Every control in a row shares one size.
    public enum ControlSize: Sendable, CaseIterable {
        /// 24 pt: options bars, chips, dense settings rows.
        case compact
        /// 28 pt: the default (toolbars, action areas, settings controls).
        case regular
        /// 32 pt: onboarding and prominent single actions.
        case large

        /// Visual height of the control's chrome.
        public var height: CGFloat {
            switch self {
            case .compact: 24
            case .regular: 28
            case .large: 32
            }
        }

        /// Minimum hit target: never below 28 pt, even when the chrome is 24.
        public var hitHeight: CGFloat { max(height, 28) }

        public var iconSize: CGFloat {
            switch self {
            case .compact: 14
            case .regular: 16
            case .large: 18
            }
        }

        public var radius: CGFloat {
            switch self {
            case .compact: 6
            case .regular: 7
            case .large: 8
            }
        }

        /// Horizontal padding between the chrome edge and its content.
        public var horizontalPadding: CGFloat {
            switch self {
            case .compact: 8
            case .regular: 10
            case .large: 14
            }
        }

        /// Gap between an icon and its label.
        public var iconLabelGap: CGFloat { self == .compact ? 4 : 6 }

        /// Label font for text inside the control.
        public var font: NSFont {
            switch self {
            case .compact: ShotzUI.Typography.label.font
            case .regular, .large: ShotzUI.Typography.control.font
            }
        }
    }

    /// Toolbar tool buttons are square and slightly larger than regular controls.
    public enum ToolMetrics {
        public static let size: CGFloat = 32
        public static let iconSize: CGFloat = 18
        public static let radius: CGFloat = 8
        /// Gap between tool buttons; groups are separated by `Space.m` plus a separator.
        public static let gap: CGFloat = 2
    }
}
