import CoreGraphics
import Foundation
import ImageIO
import ShotzCore

public enum DocumentExport {
    public enum ExportFailure: Error, Sendable { case destinationFailed, finalizeFailed }

    /// Renders the flattened document and writes it as `format`.
    /// `quality` 0…1 applies to lossy formats; `scale` multiplies base pixels.
    public static func write(
        _ document: AnnotationDocument, to url: URL, format: ImageFormat, quality: Double, scale: CGFloat
    ) throws {
        // TODO(engineer C): share a BaseImageProvider with the editor to reuse redaction caches.
        let image = try AnnotationRenderer.renderImage(document, base: BaseImageProvider(url: document.baseImageURL), outputScale: scale)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ExportFailure.destinationFailed
        }
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: 72 * document.scale * scale,
            kCGImagePropertyDPIHeight: 72 * document.scale * scale,
        ]
        if format != .png { props[kCGImageDestinationLossyCompressionQuality] = quality }
        CGImageDestinationAddImage(dest, image, props as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { throw ExportFailure.finalizeFailed }
    }
}
