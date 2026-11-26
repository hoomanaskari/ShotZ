import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

/// SHOTZ_ARROW_SHEET=<dir> [SHOTZ_ARROW_SHEET_NAME=<name>] writes an arrow review sheet:
/// five styles × five thickness steps × three lengths, curved variants, and contrast outlines.
struct ArrowSheetTests {
    /// Line widths come from a 2× capture of a 1440×900 display; the sheet itself is taller.
    static let referenceSize = CGSize(width: 2880, height: 1800)
    static let pixelSize = CGSize(width: 2880, height: 3320)

    static func sheetDocument() -> AnnotationDocument {
        var objects: [AnnotationObject] = []
        let lengths: [CGFloat] = [70, 220, 520]
        let colW: CGFloat = 640, rowH: CGFloat = 120, left: CGFloat = 60, top: CGFloat = 60
        var row = 0
        for style in ArrowStyle.allCases {
            for step in 0..<5 {
                var s = ObjectStyle.defaultStyle(for: .arrow, pixelSize: referenceSize, scale: 2)
                s.lineWidth = ObjectStyle.lineWidth(step: step, pixelSize: referenceSize)
                s.color = [RGBAColor.red, .blue, .green, .purple, .orange][row / 5 % 5]
                for (i, len) in lengths.enumerated() {
                    let y = top + CGFloat(row) * rowH + rowH / 2
                    let x = left + CGFloat(i) * colW + 40
                    let start = CGPoint(x: x, y: y + len * 0.12), end = CGPoint(x: x + len, y: y - len * 0.12)
                    let control = style == .curved ? CGPoint(x: x + len * 0.45, y: y - len * 0.35) : nil
                    objects.append(AnnotationObject(shape: .arrow(ArrowGeometry(start: start, end: end, control: control, style: style)), style: s))
                }
                row += 1
            }
        }
        // Curved variants: gentle, strong, S-like near-reverse bends; all thicknesses.
        let cx: CGFloat = 1990
        for step in 0..<5 {
            var s = ObjectStyle.defaultStyle(for: .arrow, pixelSize: referenceSize, scale: 2)
            s.lineWidth = ObjectStyle.lineWidth(step: step, pixelSize: referenceSize)
            let y = top + CGFloat(step) * 300 + 80
            for (i, bend) in [CGFloat(0.15), 0.45, 0.9].enumerated() {
                let x = cx + CGFloat(i) * 280
                let start = CGPoint(x: x, y: y + 160), end = CGPoint(x: x + 200, y: y + 120)
                let control = CGPoint(x: x + 60, y: y + 140 - 200 * bend)
                objects.append(AnnotationObject(shape: .arrow(ArrowGeometry(start: start, end: end, control: control, style: .curved)), style: s))
            }
        }
        // Contrast outline on light and dark areas.
        for (i, color) in [RGBAColor.yellow, .white, .black, .red].enumerated() {
            var s = ObjectStyle.defaultStyle(for: .arrow, pixelSize: referenceSize, scale: 2)
            s.lineWidth = ObjectStyle.lineWidth(step: 2, pixelSize: referenceSize)
            s.color = color
            s.contrastOutline = true
            let x = cx + CGFloat(i) * 210, y: CGFloat = 3170
            objects.append(AnnotationObject(shape: .arrow(ArrowGeometry(start: CGPoint(x: x, y: y + 80), end: CGPoint(x: x + 170, y: y - 60))), style: s))
        }
        return AnnotationDocument(baseImageURL: URL(filePath: "/arrows"), pixelSize: pixelSize, scale: 2, objects: objects)
    }

    /// Light background with a dark band at the bottom right (for the contrast-outline row).
    static func baseImage() -> CGImage {
        let w = Int(pixelSize.width), h = Int(pixelSize.height)
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: TestImages.sRGB,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.setFillColor(CGColor(srgbRed: 0.97, green: 0.97, blue: 0.98, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(CGColor(srgbRed: 0.18, green: 0.19, blue: 0.23, alpha: 1))
        ctx.fill(CGRect(x: 2380, y: 0, width: 500, height: 300)) // bottom right in CG's y-up space
        return ctx.makeImage()!
    }

    @Test func arrowSheet() throws {
        let doc = Self.sheetDocument()
        let image = try AnnotationRenderer.renderImage(doc, base: BaseImageProvider(image: Self.baseImage(), url: doc.baseImageURL), outputScale: 1)
        #expect(image.width == 2880 && image.height == 3320)
        guard let dir = ProcessInfo.processInfo.environment["SHOTZ_ARROW_SHEET"] else { return }
        let name = ProcessInfo.processInfo.environment["SHOTZ_ARROW_SHEET_NAME"] ?? "arrows"
        try TestImages.writePNG(image, to: URL(filePath: dir).appending(path: "\(name).png"))
    }
}
