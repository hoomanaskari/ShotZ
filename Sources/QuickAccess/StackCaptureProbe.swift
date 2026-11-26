import AppKit
import ImageIO
import ShotzCore

/// Debug-only (self-test with `-QuickAccessSelfTestCapture YES`): checks that a
/// system capture taken while the stack is visible does not contain it.
///
/// Puts an opaque magenta window of Shotz's own directly behind the stack
/// panel and runs `screencapture -R` on exactly that rectangle, so the only
/// pixels captured belong to Shotz. Then samples a card's centre.
@MainActor enum StackCaptureProbe {
    struct Result {
        let backgroundSeen: Bool
        let cardSeen: Bool
        let pngHasAlpha: Bool
        let file: URL
    }

    static var requested: Bool { DebugHooks.bool("QuickAccessSelfTestCapture") }

    static func run(panel: NSPanel, cardFrameInPanel: CGRect, output: URL) async -> Result? {
        guard CGPreflightScreenCaptureAccess(), let mainHeight = NSScreen.screens.first?.frame.height else { return nil }
        let frame = panel.frame
        let backdrop = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
        backdrop.level = .floating // below the stack's .statusBar level
        backdrop.backgroundColor = NSColor(srgbRed: 1, green: 0, blue: 1, alpha: 1)
        backdrop.isOpaque = true
        backdrop.hasShadow = false
        backdrop.ignoresMouseEvents = true
        backdrop.isReleasedWhenClosed = false
        backdrop.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        backdrop.orderFrontRegardless() // never activates Shotz
        defer { backdrop.orderOut(nil) }
        try? await Task.sleep(for: .milliseconds(400)) // let the window server composite it

        // screencapture -R takes global top-left-origin points; inset 1 pt so
        // nothing outside Shotz's own window can be captured.
        let inner = frame.insetBy(dx: 1, dy: 1)
        let rect = "\(Int(inner.minX.rounded(.up))),\(Int((mainHeight - inner.maxY).rounded(.up))),\(Int(inner.width) - 1),\(Int(inner.height) - 1)"
        let process = Process()
        process.executableURL = URL(filePath: "/usr/sbin/screencapture")
        process.arguments = ["-x", "-R", rect, "-t", "png", output.path(percentEncoded: false)]
        do {
            try process.run()
        } catch {
            return nil
        }
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            DispatchQueue.global().async {
                process.waitUntilExit()
                c.resume()
            }
        }
        guard let src = CGImageSourceCreateWithURL(output as CFURL, nil),
              let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else { return nil }
        let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any]
        let scale = CGFloat(image.width) / (CGFloat(Int(inner.width) - 1))
        // Panel point → captured image pixel (image rows run top-down).
        func pixel(_ p: CGPoint) -> CGPoint {
            CGPoint(x: (p.x - 1) * scale, y: (frame.height - 1 - p.y) * scale)
        }
        let card = pixel(CGPoint(x: cardFrameInPanel.midX, y: cardFrameInPanel.midY))
        let empty = pixel(CGPoint(x: 6, y: frame.height - 6))
        return Result(
            backgroundSeen: isMagenta(image, at: empty),
            cardSeen: !isMagenta(image, at: card),
            pngHasAlpha: (props?[kCGImagePropertyHasAlpha] as? Bool) ?? false,
            file: output
        )
    }

    private static func isMagenta(_ image: CGImage, at p: CGPoint) -> Bool {
        guard let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return false }
        // Draw so that pixel p lands on (0,0); CG's origin is bottom-left.
        ctx.draw(image, in: CGRect(x: -p.x, y: -(CGFloat(image.height) - 1 - p.y), width: CGFloat(image.width), height: CGFloat(image.height)))
        let px = data.bindMemory(to: UInt8.self, capacity: 4)
        return px[0] > 200 && px[1] < 70 && px[2] > 200
    }
}
