import AppKit
import CoreGraphics

/// ShotZ's icon set: Phosphor Icons (MIT, regular weight; see THIRD-PARTY-NOTICES) plus custom
/// glyphs drawn on the same 256-unit grid with the same 16-unit stroke, round caps and joins.
/// Every icon renders from vector paths: crisp at any size and backing scale, no resources.
public enum ShotzIcon: String, CaseIterable, Sendable {
    // Tools
    case select, arrowTool, rectangle, ellipse, line, text, highlighter, redact, counter, pen, crop, background
    // Arrow styles
    case arrowStraight, arrowCurved, arrowTapered, arrowDoubleHeaded, arrowLineWithDot
    // Rectangle fill modes
    case fillOutline, fillSolid, fillOutlineTranslucent
    // Line dash
    case lineSolid, lineDashed
    // Text decorations
    case textPlain, textOutlined, textSolidPill, textTranslucentPill
    // Highlight kinds
    case highlightFreehand, highlightRect
    // Redaction modes
    case redactPixelate, redactBlur, redactSolid
    // Thickness steps 1–5
    case thickness1, thickness2, thickness3, thickness4, thickness5
    // Actions
    case copy, save, saveAs, dragHandle, more, close, annotate, quickLook, trash, undo, redo
    case zoomIn, zoomOut, share, folder, settings, keyboard, stack, capture, window, fullscreen, area, history
    case warning, check, info, plus, minus
    // Quick-access stack
    case success, failure, showInFinder, copyPath, closeAll
    case bringForward, sendBackward, bringToFront, sendToBack
    case bold, alignLeft, alignCenter, alignRight
    case opacity, lineThickness, cornerRadius, shadow, padding, aspectRatio, gradient, palette
    case pinOff, quit, loginItem, permission
    // Settings, menus and onboarding
    case general, advanced, welcome, allInOne, restoreLastClosed, editor

    /// The five thickness glyphs in order (index = thickness step).
    public static let thicknessSteps: [ShotzIcon] = [.thickness1, .thickness2, .thickness3, .thickness4, .thickness5]

    /// Upstream Phosphor icon name, or nil for a custom Shotz glyph.
    public var phosphorName: String? {
        switch self {
        case .select: "cursor"
        case .rectangle: "rectangle"
        case .ellipse: "circle"
        case .line: "line-segment"
        case .text: "text-t"
        case .highlighter: "highlighter"
        case .redact: "checkerboard"
        case .counter: "number-circle-one"
        case .pen: "scribble"
        case .crop: "crop"
        case .copy: "copy"
        case .save: "download-simple"
        case .saveAs: "floppy-disk"
        case .dragHandle: "hand-grabbing"
        case .more: "dots-three"
        case .close: "x"
        case .annotate: "pencil-simple"
        case .quickLook: "eye"
        case .trash: "trash"
        case .undo: "arrow-u-up-left"
        case .redo: "arrow-u-up-right"
        case .zoomIn: "magnifying-glass-plus"
        case .zoomOut: "magnifying-glass-minus"
        case .share: "export"
        case .folder: "folder"
        case .settings: "gear"
        case .keyboard: "keyboard"
        case .stack: "cards"
        case .capture: "camera"
        case .window: "app-window"
        case .fullscreen: "monitor"
        case .area: "selection"
        case .history: "clock-counter-clockwise"
        case .warning: "warning"
        case .success: "check-circle"
        case .failure: "warning-circle"
        case .showInFinder: "folder-open"
        case .copyPath: "link-simple"
        case .closeAll: "x-square"
        case .check: "check"
        case .info: "info"
        case .plus: "plus"
        case .minus: "minus"
        case .bringForward: "selection-foreground"
        case .sendBackward: "selection-background"
        case .bringToFront: "arrow-line-up"
        case .sendToBack: "arrow-line-down"
        case .bold: "text-b"
        case .alignLeft: "text-align-left"
        case .alignCenter: "text-align-center"
        case .alignRight: "text-align-right"
        case .opacity: "drop-half"
        case .padding: "selection-all"
        case .aspectRatio: "frame-corners"
        case .gradient: "gradient"
        case .palette: "palette"
        case .pinOff: "push-pin-slash"
        case .quit: "power"
        case .general: "sliders"
        case .advanced: "wrench"
        case .welcome: "sparkle"
        case .allInOne: "squares-four"
        case .restoreLastClosed: "arrow-counter-clockwise"
        case .editor: "pen-nib"
        case .loginItem: "rocket-launch"
        case .permission: "shield-check"
        default: nil
        }
    }

    /// VoiceOver / tooltip-friendly description.
    public var accessibilityDescription: String {
        switch self {
        case .select: String(localized: "Select")
        case .arrowTool: String(localized: "Arrow")
        case .rectangle: String(localized: "Rectangle")
        case .ellipse: String(localized: "Ellipse")
        case .line: String(localized: "Line")
        case .text: String(localized: "Text")
        case .highlighter: String(localized: "Highlighter")
        case .redact: String(localized: "Blur or pixelate")
        case .counter: String(localized: "Counter")
        case .pen: String(localized: "Pen")
        case .crop: String(localized: "Crop")
        case .background: String(localized: "Background")
        case .arrowStraight: String(localized: "Straight arrow")
        case .arrowCurved: String(localized: "Curved arrow")
        case .arrowTapered: String(localized: "Tapered arrow")
        case .arrowDoubleHeaded: String(localized: "Double-headed arrow")
        case .arrowLineWithDot: String(localized: "Arrow with dot")
        case .fillOutline: String(localized: "Outline")
        case .fillSolid: String(localized: "Filled")
        case .fillOutlineTranslucent: String(localized: "Outline with translucent fill")
        case .lineSolid: String(localized: "Solid line")
        case .lineDashed: String(localized: "Dashed line")
        case .textPlain: String(localized: "Plain text")
        case .textOutlined: String(localized: "Outlined text")
        case .textSolidPill: String(localized: "Text on solid pill")
        case .textTranslucentPill: String(localized: "Text on translucent pill")
        case .highlightFreehand: String(localized: "Freehand highlight")
        case .highlightRect: String(localized: "Rectangle highlight")
        case .redactPixelate: String(localized: "Pixelate")
        case .redactBlur: String(localized: "Blur")
        case .redactSolid: String(localized: "Solid redaction")
        case .thickness1: String(localized: "Thickness 1")
        case .thickness2: String(localized: "Thickness 2")
        case .thickness3: String(localized: "Thickness 3")
        case .thickness4: String(localized: "Thickness 4")
        case .thickness5: String(localized: "Thickness 5")
        case .copy: String(localized: "Copy")
        case .save: String(localized: "Save")
        case .saveAs: String(localized: "Save As")
        case .dragHandle: String(localized: "Drag")
        case .more: String(localized: "More")
        case .close: String(localized: "Close")
        case .annotate: String(localized: "Annotate")
        case .quickLook: String(localized: "Quick Look")
        case .trash: String(localized: "Delete")
        case .undo: String(localized: "Undo")
        case .redo: String(localized: "Redo")
        case .zoomIn: String(localized: "Zoom in")
        case .zoomOut: String(localized: "Zoom out")
        case .share: String(localized: "Share")
        case .folder: String(localized: "Folder")
        case .settings: String(localized: "Settings")
        case .keyboard: String(localized: "Keyboard shortcuts")
        case .stack: String(localized: "Quick access stack")
        case .capture: String(localized: "Capture")
        case .window: String(localized: "Window")
        case .fullscreen: String(localized: "Fullscreen")
        case .area: String(localized: "Area")
        case .history: String(localized: "History")
        case .warning: String(localized: "Warning")
        case .success: String(localized: "Succeeded")
        case .failure: String(localized: "Failed")
        case .showInFinder: String(localized: "Show in Finder")
        case .copyPath: String(localized: "Copy file path")
        case .closeAll: String(localized: "Close all")
        case .check: String(localized: "Done")
        case .info: String(localized: "Information")
        case .plus: String(localized: "Add")
        case .minus: String(localized: "Remove")
        case .bringForward: String(localized: "Bring forward")
        case .sendBackward: String(localized: "Send backward")
        case .bringToFront: String(localized: "Bring to front")
        case .sendToBack: String(localized: "Send to back")
        case .bold: String(localized: "Bold")
        case .alignLeft: String(localized: "Align left")
        case .alignCenter: String(localized: "Align centre")
        case .alignRight: String(localized: "Align right")
        case .opacity: String(localized: "Opacity")
        case .lineThickness: String(localized: "Thickness")
        case .cornerRadius: String(localized: "Corner radius")
        case .shadow: String(localized: "Shadow")
        case .padding: String(localized: "Padding")
        case .aspectRatio: String(localized: "Aspect ratio")
        case .gradient: String(localized: "Gradient")
        case .palette: String(localized: "Colours")
        case .pinOff: String(localized: "Unpin")
        case .quit: String(localized: "Quit")
        case .general: String(localized: "General")
        case .advanced: String(localized: "Advanced")
        case .welcome: String(localized: "Welcome")
        case .allInOne: String(localized: "All-in-one")
        case .restoreLastClosed: String(localized: "Restore last closed")
        case .editor: String(localized: "Editor")
        case .loginItem: String(localized: "Launch at login")
        case .permission: String(localized: "Permission")
        }
    }

    /// The glyph's layers on the 256-unit grid (y down). Translucent layers carry opacity < 1.
    var glyphLayers: [IconLayer] {
        if let name = phosphorName {
            return IconGlyph.phosphor(name)
        }
        return CustomGlyphs.layers(for: self)
    }
}
