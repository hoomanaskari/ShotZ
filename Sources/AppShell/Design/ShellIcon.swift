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

    /// Toolbar (preference tab) image: the glyph at `glyph` points centred on a
    /// `canvas`-point template image. ShotzIcon glyphs fill their whole box,
    /// unlike SF Symbols, so drawing them smaller on the usual canvas matches
    /// the optical size of the system's preference-toolbar icons (≈13 pt of ink).
    public func toolbarImage(glyph: CGFloat = 15, canvas: CGFloat = 18) -> NSImage {
        let source = shotzIcon.image(pointSize: glyph)
        let image = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
            let inset = (canvas - glyph) / 2
            source.draw(in: rect.insetBy(dx: inset, dy: inset))
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = source.accessibilityDescription
        return image
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

    /// For `--debug-snapshot-ui`: the Settings toolbar images side by side at
    /// `scale` (1 or 2) on a light background, to check optical size per resolution.
    @MainActor public static func debugToolbarStrip(_ icons: [ShellIcon], scale: CGFloat) -> Data? {
        let cell: CGFloat = 30
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(cell * CGFloat(icons.count) * scale),
                                         pixelsHigh: Int(cell * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)
        else { return nil }
        rep.size = NSSize(width: cell * CGFloat(icons.count), height: cell)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.93, alpha: 1).setFill()
        NSRect(origin: .zero, size: rep.size).fill()
        for (i, icon) in icons.enumerated() {
            let image = icon.toolbarImage()
            let tinted = NSImage(size: image.size, flipped: false) { rect in
                image.draw(in: rect)
                NSColor(white: 0.25, alpha: 1).set()
                rect.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: CGFloat(i) * cell + 6, y: 6, width: 18, height: 18))
        }
        NSGraphicsContext.restoreGraphicsState()
        return rep.representation(using: .png, properties: [:])
    }
}
