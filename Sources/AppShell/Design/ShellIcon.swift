import AppKit
import ShotzCore
import SwiftUI

/// Every icon the shell draws (Settings tabs, status menu, onboarding, rows),
/// as roles mapped onto the shared `ShotzIcon` set (one family, one weight;
/// no SF Symbols). Call sites name a role; only `shotzIcon` knows the glyph.
public enum ShellIcon: String, CaseIterable, Sendable {
    // Settings tabs
    case general, shortcuts, quickAccess, capture, editor, advanced
    // Status menu
    case captureArea, captureWindow, captureFullscreen, captureAllInOne
    case history, openInEditor, restore, settings, quit
    // Onboarding, rows and status
    case welcome, screenRecording, keyboard, launchAtLogin, warning, checkmark, folder, clear, info

    public var shotzIcon: ShotzIcon {
        switch self {
        case .general: .general
        case .shortcuts: .keyboard
        case .quickAccess: .stack
        case .capture: .capture
        case .editor: .editor
        case .advanced: .advanced
        case .captureArea: .area
        case .captureWindow: .window
        case .captureFullscreen: .fullscreen
        case .captureAllInOne: .allInOne
        case .history: .history
        case .openInEditor: .annotate
        case .restore: .restoreLastClosed
        case .settings: .settings
        case .quit: .quit
        case .welcome: .welcome
        case .screenRecording: .permission
        case .keyboard: .keyboard
        case .launchAtLogin: .loginItem
        case .warning: .warning
        case .checkmark: .check
        case .folder: .folder
        case .clear: .close
        case .info: .info
        }
    }

    /// Template image for menus (16 pt) and toolbars.
    public func nsImage(pointSize: CGFloat = 16) -> NSImage {
        shotzIcon.image(pointSize: pointSize)
    }

    /// The icon as a SwiftUI view at `size` points, tinted by the foreground style.
    public func view(size: CGFloat = 13) -> some View {
        Image(nsImage: nsImage(pointSize: size))
            .renderingMode(.template)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
