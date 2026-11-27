import AnnotationKit
import AppKit
import Foundation
import ShotzCore
import ShotzUI
import Testing
import ShotzTestSupport
@testable import AnnotationEditor

/// Review renders of the Background panel and canvas (0.1.2): a real editor window that is never
/// shown (nothing appears on screen and nothing is activated), driven by the editor script runner's
/// panel commands, which press the real controls with in-process mouse events.
///
/// Only runs when `SHOTZ_REVIEW_DIR` names an output folder (scripts/background-panel-review.sh).
@MainActor
struct BackgroundReviewRenders {
    nonisolated static let outputDir = ProcessInfo.processInfo.environment["SHOTZ_REVIEW_DIR"]

    private func makeController() throws -> EditorWindowController {
        _ = NSApplication.shared
        let defaults = MemoryDefaults()
        let size = CGSize(width: 900, height: 560)
        let ctx = try #require(CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        // A plain "window" with a title bar and some blocks, so position and padding read clearly.
        ctx.setFillColor(CGColor(gray: 0.97, alpha: 1)); ctx.fill(CGRect(origin: .zero, size: size))
        ctx.setFillColor(CGColor(gray: 0.86, alpha: 1)); ctx.fill(CGRect(x: 0, y: size.height - 44, width: size.width, height: 44))
        for (i, c) in [CGColor(red: 0.95, green: 0.36, blue: 0.33, alpha: 1), CGColor(red: 0.98, green: 0.75, blue: 0.2, alpha: 1),
                       CGColor(red: 0.3, green: 0.78, blue: 0.4, alpha: 1)].enumerated() {
            ctx.setFillColor(c); ctx.fillEllipse(in: CGRect(x: 18 + CGFloat(i) * 22, y: size.height - 30, width: 14, height: 14))
        }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.45, blue: 0.9, alpha: 1)); ctx.fill(CGRect(x: 40, y: 300, width: 360, height: 160))
        ctx.setFillColor(CGColor(gray: 0.75, alpha: 1))
        for row in 0..<6 { ctx.fill(CGRect(x: 440, y: 440 - CGFloat(row) * 34, width: 400 - CGFloat(row % 3) * 60, height: 14)) }
        ctx.setFillColor(CGColor(red: 0.9, green: 0.5, blue: 0.2, alpha: 1)); ctx.fill(CGRect(x: 40, y: 40, width: 820, height: 200))
        let image = try #require(ctx.makeImage())
        let url = URL(filePath: "/tmp/shotz-background-review.png")
        let env = EditorEnvironment(
            settings: SettingsStore(defaults: defaults), exporter: DefaultExportService(),
            library: ToolSettingsLibrary(defaults: defaults), backgroundPresets: BackgroundPresets(defaults: defaults),
            openImage: { _ in }, openClipboard: {}
        )
        let doc = AnnotationDocument(baseImageURL: url, pixelSize: size, scale: 1)
        return EditorWindowController(store: DocumentStore(document: doc), image: image,
                                      base: BaseImageProvider(image: image, url: url), title: "Background review", documentURL: nil, env: env)
    }

    /// The script for one theme: slider positions reached by dragging, then every grid cell with
    /// Auto and with fixed aspects, auto-balance on and off, corners and angle.
    static func script(theme: String, into dir: String) -> String {
        func shot(_ name: String) -> String { "snapshot \"\(dir)/\(theme)-\(name).png\" 2" }
        var lines = ["appearance \(theme)", "size 1280 800", "background on", "panel", "wait 300", "zoom fit", shot("00-default")]
        // Padding: press at 50 % of the track, drag up to 90 %, then back to 20 % and 0 %.
        lines += ["panelslider \"Padding\" 50 70 90", shot("01-padding-90pct-of-track"),
                  "panelslider \"Padding\" 90 60 20", shot("02-padding-dragged-back-20pct"),
                  "panelslider \"Padding\" 20 10 0", shot("03-padding-0"),
                  "panelslider \"Padding\" 0 20 40", shot("04-padding-40pct-of-track")]
        let cells: [(String, String)] = [("Align top left", "tl"), ("Align top", "t"), ("Align top right", "tr"), ("Align left", "l"),
                                         ("Align centre", "c"), ("Align right", "r"), ("Align bottom left", "bl"),
                                         ("Align bottom", "b"), ("Align bottom right", "br")]
        let aspects = [(0, "auto"), (1, "1x1"), (2, "4x3"), (3, "16x9"), (4, "3x2")]
        for (index, aspect) in aspects {
            lines += ["panelsegment \"Aspect\" \(index) \(aspects.count)", "zoom fit"]
            for (label, short) in cells where aspect == "auto" || ["tl", "c", "br", "t", "r"].contains(short) {
                lines += ["panelclick \"\(label)\"", "zoom fit", shot("10-position-\(aspect)-\(short)")]
            }
        }
        lines += ["panelsegment \"Aspect\" 3 5", "panelclick \"Align bottom right\"", "panelclick \"Auto-balance\"", "zoom fit",
                  shot("20-16x9-br-autobalance-toggled"), "panelclick \"Auto-balance\"",
                  "panelsegment \"Aspect\" 0 5", "panelclick \"Align centre\"",
                  "panelslider \"Corners\" 10 50 80", shot("30-corners-80pct"),
                  "panelslider \"Angle\" 50 75 25", shot("31-angle-25pct"),
                  "panelslider \"Padding\" 40 0", "zoom fit", shot("40-no-padding-auto-position-disabled")]
        return lines.joined(separator: "\n")
    }

    @Test(.enabled(if: outputDir != nil, "set SHOTZ_REVIEW_DIR to render"))
    func renderBackgroundPanelReview() async throws {
        let dir = try #require(Self.outputDir)
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        for theme in ["light", "dark"] {
            let controller = try makeController()
            await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
                EditorScriptRunner.run(Self.script(theme: theme, into: dir), on: controller) { done.resume() }
            }
            #expect(controller.backgroundPanel != nil)
            controller.window?.close()
        }
        let pngs = try FileManager.default.contentsOfDirectory(atPath: dir).filter { $0.hasSuffix(".png") }
        #expect(pngs.count >= 2 * 30, "\(pngs.count) renders")
    }
}
