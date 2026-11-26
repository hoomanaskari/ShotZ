import CoreGraphics
import Foundation
import ImageIO
import ShotzCore
import UniformTypeIdentifiers

public enum DocumentExport {
    public enum ExportFailure: Error, Sendable { case destinationFailed, finalizeFailed }

    /// Renders the flattened document and writes it as `format`.
    /// `quality` 0…1 applies to lossy formats; `scale` multiplies base pixels
    /// (1 = native; `1 / document.scale` = 1×).
    public static func write(
        _ document: AnnotationDocument, to url: URL, format: ImageFormat, quality: Double, scale: CGFloat
    ) throws {
        try write(document, base: BaseImageProvider(url: document.baseImageURL), to: url, format: format, quality: quality, scale: scale)
    }

    /// As `write(_:to:format:quality:scale:)`, reusing the editor's provider (and its redaction cache).
    public static func write(
        _ document: AnnotationDocument, base: BaseImageProvider, to url: URL, format: ImageFormat, quality: Double, scale: CGFloat
    ) throws {
        let image = try render(document, base: base, format: format, scale: scale)
        guard let dest = CGImageDestinationCreateWithURL(url as CFURL, format.utType.identifier as CFString, 1, nil) else {
            throw ExportFailure.destinationFailed
        }
        CGImageDestinationAddImage(dest, image, properties(document, format: format, quality: quality, scale: scale))
        guard CGImageDestinationFinalize(dest) else { throw ExportFailure.finalizeFailed }
    }

    /// Encoded bytes (for the pasteboard or a drag), same rules as `write`.
    public static func data(
        _ document: AnnotationDocument, base: BaseImageProvider, format: ImageFormat, quality: Double, scale: CGFloat
    ) throws -> Data {
        let image = try render(document, base: base, format: format, scale: scale)
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out as CFMutableData, format.utType.identifier as CFString, 1, nil) else {
            throw ExportFailure.destinationFailed
        }
        CGImageDestinationAddImage(dest, image, properties(document, format: format, quality: quality, scale: scale))
        guard CGImageDestinationFinalize(dest) else { throw ExportFailure.finalizeFailed }
        return out as Data
    }

    /// The flattened image; JPEG has no alpha, so it is matted onto white instead of black.
    static func render(_ document: AnnotationDocument, base: BaseImageProvider, format: ImageFormat, scale: CGFloat) throws -> CGImage {
        try AnnotationRenderer.renderImage(document, base: base, outputScale: scale, opaqueMatte: format == .jpeg ? .white : nil)
    }

    static func properties(_ document: AnnotationDocument, format: ImageFormat, quality: Double, scale: CGFloat) -> CFDictionary {
        // DPI records points: a 2× capture exported natively is 144 dpi, at 1× it is 72 dpi.
        let dpi = 72 * max(document.scale * scale, 0.01)
        var props: [CFString: Any] = [
            kCGImagePropertyDPIWidth: dpi,
            kCGImagePropertyDPIHeight: dpi,
        ]
        if format != .png { props[kCGImageDestinationLossyCompressionQuality] = min(max(quality, 0), 1) }
        return props as CFDictionary
    }
}
