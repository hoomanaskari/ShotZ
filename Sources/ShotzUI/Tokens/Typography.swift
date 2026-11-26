import AppKit
import SwiftUI

extension ShotzUI {
    /// The type ramp. System font throughout; values use monospaced digits so they don't jitter.
    public enum Typography: CaseIterable, Sendable {
        /// 15 semibold: pane and onboarding titles.
        case title
        /// 13 semibold: section headers above grouped cards.
        case sectionHeader
        /// 13 regular: settings row titles, body copy.
        case body
        /// 13 medium: text inside regular and large controls.
        case control
        /// 12 medium: compact controls, chips, segment labels.
        case label
        /// 11 regular: help text, captions, tooltips.
        case caption
        /// 12 medium, monospaced digits: slider values, zoom, sizes.
        case value

        public var size: CGFloat {
            switch self {
            case .title: 15
            case .sectionHeader, .body, .control: 13
            case .label, .value: 12
            case .caption: 11
            }
        }

        public var weight: NSFont.Weight {
            switch self {
            case .title, .sectionHeader: .semibold
            case .body, .caption: .regular
            case .control, .label, .value: .medium
            }
        }

        public var font: NSFont {
            self == .value
                ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight)
                : NSFont.systemFont(ofSize: size, weight: weight)
        }

        public var swiftUIFont: Font {
            let base = Font.system(size: size, weight: Font.Weight(weight))
            return self == .value ? base.monospacedDigit() : base
        }
    }
}

extension Font.Weight {
    init(_ w: NSFont.Weight) {
        switch w {
        case .semibold: self = .semibold
        case .medium: self = .medium
        case .bold: self = .bold
        default: self = .regular
        }
    }
}
