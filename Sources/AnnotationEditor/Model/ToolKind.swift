import AnnotationKit
import Foundation

/// Every editor tool (SPEC §5.3), with its single-key shortcut.
enum ToolKind: String, CaseIterable, Codable, Sendable {
    case select, arrow, rectangle, ellipse, line, text, highlighter, redact, counter, pen, crop

    /// Single-key shortcut (lowercase). Background (G) is a panel, handled separately.
    var key: Character {
        switch self {
        case .select: "v"
        case .arrow: "a"
        case .rectangle: "r"
        case .ellipse: "o"
        case .line: "l"
        case .text: "t"
        case .highlighter: "h"
        case .redact: "b"
        case .counter: "n"
        case .pen: "p"
        case .crop: "c"
        }
    }

    static func forKey(_ key: Character) -> ToolKind? {
        allCases.first { $0.key == key }
    }

    var title: String {
        switch self {
        case .select: String(localized: "Select")
        case .arrow: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .line: String(localized: "Line")
        case .text: String(localized: "Text")
        case .highlighter: String(localized: "Highlighter")
        case .redact: String(localized: "Blur and Pixelate")
        case .counter: String(localized: "Counter")
        case .pen: String(localized: "Pen")
        case .crop: String(localized: "Crop")
        }
    }

    /// SF Symbol name for the tool strip.
    var symbolName: String {
        switch self {
        case .select: "cursorarrow"
        case .arrow: "arrow.up.right"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line.diagonal"
        case .text: "textformat"
        case .highlighter: "highlighter"
        case .redact: "eye.slash"
        case .counter: "1.circle"
        case .pen: "scribble"
        case .crop: "crop"
        }
    }

    /// Tools that create objects (and stay armed after drawing).
    var isDrawingTool: Bool {
        switch self {
        case .select, .crop: false
        default: true
        }
    }

    /// The tool that creates an object of this shape (for restyling / options).
    static func forShape(_ shape: AnnotationObject.Shape) -> ToolKind {
        switch shape {
        case .arrow: .arrow
        case .rectangle: .rectangle
        case .ellipse: .ellipse
        case .line: .line
        case .text: .text
        case .highlight: .highlighter
        case .redact: .redact
        case .counter: .counter
        case .pen: .pen
        }
    }
}
