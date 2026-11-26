import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

/// Renders every shape and style over a synthetic image. Set SHOTZ_SHOWCASE=1 to also write
/// build/annotationkit-showcase.png (and a background variant) for visual inspection.
struct ShowcaseTests {
    static func showcaseDocument(width: CGFloat = 2400, height: CGFloat = 1500) -> AnnotationDocument {
        let size = CGSize(width: width, height: height)
        func style(_ kind: AnnotationKind, _ body: (inout ObjectStyle) -> Void = { _ in }) -> ObjectStyle {
            var s = ObjectStyle.defaultStyle(for: kind, pixelSize: size, scale: 2)
            body(&s)
            return s
        }
        var objects: [AnnotationObject] = []
        func add(_ shape: AnnotationObject.Shape, _ s: ObjectStyle) { objects.append(AnnotationObject(shape: shape, style: s)) }
        // Row 1: arrows, five styles, plus a contrast-outlined and a thick one.
        let arrowStyles: [ArrowStyle] = [.straight, .curved, .tapered, .doubleHeaded, .lineWithDot]
        for (i, a) in arrowStyles.enumerated() {
            let x = 80 + CGFloat(i) * 300
            add(.arrow(ArrowGeometry(start: CGPoint(x: x, y: 260), end: CGPoint(x: x + 220, y: 80),
                                     control: a == .curved ? CGPoint(x: x + 40, y: 110) : nil, style: a)),
                style(.arrow) { $0.color = RGBAColor.presets[i] })
        }
        add(.arrow(ArrowGeometry(start: CGPoint(x: 1600, y: 280), end: CGPoint(x: 1850, y: 80))),
            style(.arrow) { $0.color = .yellow; $0.contrastOutline = true; $0.lineWidth = ObjectStyle.lineWidth(step: 3, pixelSize: size) })
        add(.arrow(ArrowGeometry(start: CGPoint(x: 1950, y: 280), end: CGPoint(x: 2300, y: 100), style: .tapered)),
            style(.arrow) { $0.lineWidth = ObjectStyle.lineWidth(step: 4, pixelSize: size); $0.contrastOutline = true })
        // Row 2: boxes.
        add(.rectangle(CGRect(x: 80, y: 340, width: 260, height: 160), cornerRadius: 0), style(.rectangle))
        add(.rectangle(CGRect(x: 380, y: 340, width: 260, height: 160), cornerRadius: 24), style(.rectangle) { $0.color = .blue; $0.fill = .filled; $0.opacity = 0.85 })
        add(.rectangle(CGRect(x: 680, y: 340, width: 260, height: 160), cornerRadius: 14), style(.rectangle) { $0.color = .green; $0.fill = .outlineTranslucentFill })
        add(.ellipse(CGRect(x: 980, y: 340, width: 260, height: 160)), style(.ellipse) { $0.color = .purple })
        add(.ellipse(CGRect(x: 1280, y: 340, width: 200, height: 160)), style(.ellipse) { $0.color = .orange; $0.fill = .filled })
        add(.line(start: CGPoint(x: 1540, y: 360), end: CGPoint(x: 1900, y: 480)), style(.line) { $0.color = .black })
        add(.line(start: CGPoint(x: 1540, y: 480), end: CGPoint(x: 1900, y: 360)), style(.line) { $0.dash = .dashed; $0.color = .blue })
        add(.rectangle(CGRect(x: 1960, y: 340, width: 360, height: 160), cornerRadius: 8), style(.rectangle) { $0.dash = .dashed; $0.color = .black })
        // Row 3: text in four decorations, wrapping, alignment, bold, emoji.
        let decorations: [TextStyle.Decoration] = [.plain, .outlined, .solidPill, .translucentPill]
        for (i, d) in decorations.enumerated() {
            add(.text(TextBox(origin: CGPoint(x: 80 + CGFloat(i) * 520, y: 560), string: "Shotz \(d.rawValue) 👋",
                              style: TextStyle(decoration: d, isBold: i % 2 == 1))),
                style(.text) { $0.color = i == 1 ? .white : (i == 3 ? .yellow : .red) })
        }
        add(.text(TextBox(origin: CGPoint(x: 1960, y: 700), wrapWidth: 380,
                          string: "Wrapped and centred text that flows onto several lines ✨", style: TextStyle(decoration: .solidPill, alignment: .center))),
            style(.text) { $0.color = .blue })
        // Row 4 (on the dark band at 62–72 %): highlights, counters, pen.
        add(.highlight(.rect(CGRect(x: 900, y: 1040, width: 760, height: 64))), style(.highlighter))
        let marker: [CGPoint] = (0...40).map { (i: Int) -> CGPoint in
            let t = CGFloat(i)
            return CGPoint(x: 900 + t * 18, y: 1150 + sin(t / 5) * 12)
        }
        add(.highlight(.freehand(StrokeSmoothing.smooth(marker))),
            style(.highlighter) { $0.color = .green })
        for i in 0..<4 {
            let c = CGPoint(x: 1100 + CGFloat(i) * 150, y: 820)
            add(.counter(CounterGeometry(center: c, tail: i == 3 ? CGPoint(x: c.x + 90, y: c.y + 110) : nil, value: i + 1,
                                         numbering: i == 2 ? .alphabetic : .numeric)),
                style(.counter) { $0.color = [RGBAColor.red, .blue, .yellow, .green][i] })
        }
        add(.counter(CounterGeometry(center: CGPoint(x: 1800, y: 820), value: 12)), style(.counter) { $0.color = .white })
        var wave: [CGPoint] = []
        for i in 0...60 {
            let t = CGFloat(i)
            let jitter = CGFloat(i % 3)
            wave.append(CGPoint(x: 120 + t * 12, y: 820 + sin(t / 4) * 50 + jitter))
        }
        add(.pen(StrokeSmoothing.smooth(wave)), style(.pen) { $0.color = .orange })
        // Redactions over the sample text (drawn beneath everything else regardless of order).
        add(.redact(CGRect(x: 50, y: 1190, width: 700, height: 70), .pixelate), style(.redact))
        add(.redact(CGRect(x: 50, y: 1262, width: 700, height: 66), .blur), style(.redact))
        add(.redact(CGRect(x: 380, y: 1330, width: 360, height: 66), .solid), style(.redact))
        add(.arrow(ArrowGeometry(start: CGPoint(x: 1100, y: 1400), end: CGPoint(x: 760, y: 1300))), style(.arrow))
        return AnnotationDocument(baseImageURL: URL(filePath: "/tmp/showcase-base.png"), pixelSize: size, scale: 2, objects: objects)
    }

    static func base(for doc: AnnotationDocument) -> BaseImageProvider {
        BaseImageProvider(image: TestImages.base(width: Int(doc.pixelSize.width), height: Int(doc.pixelSize.height)), url: doc.baseImageURL)
    }

    @Test func showcaseRenders() throws {
        let doc = Self.showcaseDocument()
        let base = Self.base(for: doc)
        let image = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1)
        #expect(image.width == 2400 && image.height == 1500)
        var framed = doc
        framed.background = BackgroundStyle(fill: .gradient(GradientPreset.all[1].fill), padding: 0.06, cornerRadius: 28, shadow: .strong, aspect: .sixteenNine)
        let framedImage = try AnnotationRenderer.renderImage(framed, base: base, outputScale: 0.5)
        if ProcessInfo.processInfo.environment["SHOTZ_SHOWCASE"] == "1" {
            try TestImages.writePNG(image, to: TestImages.packageRoot.appending(path: "build/annotationkit-showcase.png"))
            try TestImages.writePNG(framedImage, to: TestImages.packageRoot.appending(path: "build/annotationkit-showcase-background.png"))
        }
    }
}
