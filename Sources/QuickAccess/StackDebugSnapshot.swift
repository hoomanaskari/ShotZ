import AppKit
import ImageIO
import ShotzCore
import UniformTypeIdentifiers

/// Debug aid, active only with `-QuickAccessDebug YES`: posting the distributed
/// notification `com.pixelforty.shotz.debug.snapshotStack` with a folder path as object
/// renders each stack panel's own layer tree to `<folder>/stack-<display>.png`
/// (no screen content is captured), and logs the card state.
@MainActor final class StackDebugSnapshot {
    static let enabled = DebugHooks.bool("QuickAccessDebug")   // ShotZ Dev only; never in the production app
    private var observer: NSObjectProtocol?

    init(panels: @escaping @MainActor () -> [UInt32: NSPanel], log: @escaping @MainActor (String) -> Void) {
        guard Self.enabled else { return }
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.pixelforty.shotz.debug.snapshotStack"), object: nil, queue: .main
        ) { note in
            let folder = note.object as? String
            MainActor.assumeIsolated {
                guard let folder else { return }
                for (display, panel) in panels() {
                    let url = URL(filePath: folder).appending(path: "stack-\(display).png")
                    let ok = Self.render(panel, to: url)
                    log("Snapshot \(url.lastPathComponent) \(ok ? "written" : "failed"), panel \(NSStringFromRect(panel.frame)), key \(panel.isKeyWindow)")
                }
            }
        }
    }

    /// Renders `panel` to `url` over a neutral grey. When the panel is
    /// shareable and Screen Recording is granted, the window itself is
    /// captured (`screencapture -l`: only this window's pixels), which shows
    /// materials and vibrancy exactly; otherwise its layer tree is drawn
    /// (no blur materials).
    static func render(_ panel: NSPanel, to url: URL) -> Bool {
        if panel.sharingType != .none, CGPreflightScreenCaptureAccess(), captureWindow(panel, to: url) { return true }
        return renderLayers(panel, to: url)
    }

    private static func captureWindow(_ panel: NSPanel, to url: URL) -> Bool {
        let raw = url.deletingLastPathComponent().appending(path: ".raw-\(url.lastPathComponent)")
        defer { try? FileManager.default.removeItem(at: raw) } // scratch file
        let p = Process()
        p.executableURL = URL(filePath: "/usr/sbin/screencapture")
        p.arguments = ["-x", "-o", "-l", String(panel.windowNumber), "-t", "png", raw.path(percentEncoded: false)]
        do { try p.run() } catch { return false }
        p.waitUntilExit()
        guard let src = CGImageSourceCreateWithURL(raw as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil),
              let ctx = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        guard let out = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, out, nil)
        return CGImageDestinationFinalize(dest)
    }

    private static func renderLayers(_ panel: NSPanel, to url: URL) -> Bool {
        guard let view = panel.contentView, let layer = view.layer else { return false }
        let scale = panel.backingScaleFactor
        let w = Int(view.bounds.width * scale), h = Int(view.bounds.height * scale)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
        // A neutral mid-grey backdrop so shadows and borders are visible.
        ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.scaleBy(x: scale, y: scale)
        view.displayIfNeeded()
        layer.render(in: ctx)
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, nil)
        return CGImageDestinationFinalize(dest)
    }
}
