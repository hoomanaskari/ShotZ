import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

/// 5120×2880 export time budget (ARCHITECTURE §9). Serialized and best-of-3 so a loaded
/// machine (parallel tests, other builds) doesn't fail it, while a real regression still does.
@Suite(.serialized)
struct ExportPerformanceTests {
    /// Measured best-of-3 on the dev Mac under a load average of ~10: ≈ 51 ms in a debug build,
    /// ≈ 50 ms in release (the time is Core Graphics / Core Image work, not Swift loops). The budget
    /// is ~5× that: headroom for a loaded machine, but a real regression still fails.
    static let budget = Duration.milliseconds(250)

    @Test func fiveKExportWithFiftyObjectsIsFast() throws {
        let base = BaseImageProvider(image: TestImages.base(width: 5120, height: 2880), url: URL(filePath: "/x"))
        var doc = ShowcaseTests.showcaseDocument(width: 5120, height: 2880)
        let template = doc.objects
        doc.objects = (0..<50).map { i in
            template[i % template.count].duplicated(offsetBy: CGVector(dx: CGFloat(i % 4) * 600, dy: CGFloat(i / 25) * 1300))
        }
        // Large redactions dominate the cost; include one of each kind at 5K size.
        doc.objects += [
            AnnotationObject(shape: .redact(CGRect(x: 100, y: 1800, width: 1600, height: 500), .pixelate)),
            AnnotationObject(shape: .redact(CGRect(x: 1800, y: 1800, width: 1600, height: 500), .blur)),
            AnnotationObject(shape: .redact(CGRect(x: 3500, y: 1800, width: 1500, height: 500), .solid)),
        ]
        doc.background = BackgroundStyle(fill: .gradient(GradientPreset.all[0].fill), padding: 0.05, shadow: .soft)
        _ = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1) // warm fonts, Core Image, opacity scan
        let clock = ContinuousClock()
        var best = Duration.seconds(60)
        var image: CGImage?
        for _ in 0..<3 {
            base.clearCache() // every run recomputes the redactions (a cold export)
            best = min(best, try clock.measure { image = try AnnotationRenderer.renderImage(doc, base: base, outputScale: 1) })
        }
        #expect(image?.width == 5632 && image?.height == 3392)
        #expect(best < Self.budget, "5K export best-of-3 took \(best)")
    }
}
