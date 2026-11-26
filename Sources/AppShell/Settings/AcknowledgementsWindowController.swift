import AppKit
import ShotzCore
import ShotzUI

/// Settings ▸ Advanced ▸ Acknowledgements: ShotZ's licence and the third-party notices
/// (Phosphor Icons, Sparkle), read from the copies bundle.sh puts in Contents/Resources.
///
/// A ShotZ window rather than the default text viewer: the files have no extension (so Launch
/// Services may not know what opens them), nothing else gets launched, and the text uses ShotZ's
/// own type and colours. Read-only and selectable, so a licence can still be copied.
@MainActor public final class AcknowledgementsWindowController: NSObject, NSWindowDelegate {
    private var window: ShellWindow?
    private let bundle: Bundle

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        super.init()
    }

    public func show() {
        let window = self.window ?? makeWindow()
        self.window = window
        if !window.isVisible { window.center() }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    /// For `--debug-snapshot-ui`: the window off screen (never ordered in).
    public func debugRender(appearance: NSAppearance.Name = .aqua, scale: CGFloat = 2) async -> Data? {
        let window = makeWindow()
        window.appearance = NSAppearance(named: appearance)
        return await OffscreenRenderer.capture(window, scale: scale)
    }

    /// The text shown: ShotZ's licence, then the third-party notices.
    static func text(bundle: Bundle) -> String {
        let parts = ["LICENSE", "THIRD-PARTY-NOTICES"].map { name -> String in
            guard let url = bundle.url(forResource: name, withExtension: nil),
                  let text = try? String(contentsOf: url, encoding: .utf8), !text.isEmpty
            else { return String(localized: "\(name) is not included in this build.") }
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "ShotZ\n=====\n\n" + parts.joined(separator: "\n\n\n")
    }

    private func makeWindow() -> ShellWindow {
        let size = NSSize(width: 640, height: 560)
        let window = ShellWindow(contentRect: NSRect(origin: .zero, size: size),
                                 styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        window.title = String(localized: "Acknowledgements")
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.delegate = self

        let scroll = NSScrollView(frame: NSRect(origin: .zero, size: size))
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.borderType = .noBorder
        scroll.drawsBackground = true
        scroll.backgroundColor = ShotzUI.Palette.windowBackground
        scroll.autoresizingMask = [.width, .height]

        let text = NSTextView(frame: NSRect(origin: .zero, size: size))
        text.isEditable = false
        text.isSelectable = true
        text.isRichText = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: ShotzUI.Space.xl, height: ShotzUI.Space.xl)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        text.autoresizingMask = [.width]
        text.textContainer?.widthTracksTextView = true
        // Licence texts are laid out in fixed-width columns; ShotZ's body size, monospaced.
        text.font = NSFont.monospacedSystemFont(ofSize: ShotzUI.Typography.label.size, weight: .regular)
        text.textColor = ShotzUI.Palette.textPrimary
        text.string = Self.text(bundle: bundle)
        text.setAccessibilityLabel(String(localized: "Licences"))
        scroll.documentView = text

        window.contentView = scroll
        return window
    }
}
