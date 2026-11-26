import AppKit
import SwiftUI

/// Every icon the shell draws (Settings tabs, status menu, onboarding).
/// PLACEHOLDER: SF Symbols until engineer C's shared `ShotzIcon` set (Phosphor,
/// one weight) lands in ShotzCore; then only `symbolName` below changes to
/// `ShotzIcon` lookups and every call site stays as it is.
public enum ShellIcon: String, CaseIterable, Sendable {
    // Settings tabs
    case general, shortcuts, quickAccess, capture, editor, advanced
    // Status menu
    case captureArea, captureWindow, captureFullscreen, captureAllInOne
    case history, openInEditor, restore, settings, quit
    // Onboarding and status
    case welcome, screenRecording, keyboard, launchAtLogin, warning, checkmark, folder

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .shortcuts: "command"
        case .quickAccess: "rectangle.stack"
        case .capture: "camera.viewfinder"
        case .editor: "pencil.tip.crop.circle"
        case .advanced: "slider.horizontal.3"
        case .captureArea: "rectangle.dashed"
        case .captureWindow: "macwindow"
        case .captureFullscreen: "display"
        case .captureAllInOne: "square.grid.2x2"
        case .history: "clock.arrow.circlepath"
        case .openInEditor: "pencil"
        case .restore: "arrow.uturn.backward"
        case .settings: "gearshape"
        case .quit: "power"
        case .welcome: "sparkles"
        case .screenRecording: "rectangle.dashed.badge.record"
        case .keyboard: "keyboard"
        case .launchAtLogin: "power"
        case .warning: "exclamationmark.triangle.fill"
        case .checkmark: "checkmark.circle.fill"
        case .folder: "folder"
        }
    }

    /// Template image for menus and toolbars.
    public func nsImage(pointSize: CGFloat = 15, weight: NSFont.Weight = .regular) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    public var image: Image { Image(systemName: symbolName) }
}
