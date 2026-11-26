import CoreGraphics
import Foundation
import ImageIO
import ShotzCore

/// What a card shows and delivers (SPEC §4.6). A card returning from the
/// editor shows the flattened annotated image (`imageURL`); Copy, Save, Quick
/// Look, drag-out, the thumbnail and the size caption all use it, while
/// Annotate and history keep using the original capture. Pure; unit-tested.
struct CardSource: Equatable, Sendable {
    let capture: CaptureResult
    /// The flattened annotated image, if the capture has edits.
    let imageURL: URL?
    /// Pixel size of the delivered image.
    let pixelSize: CGSize

    /// - Parameter pixelSizeOf: reads an image's pixel size (header only).
    init(capture: CaptureResult, imageURL: URL?, pixelSizeOf: (URL) -> CGSize? = CardSource.headerPixelSize) {
        self.capture = capture
        self.imageURL = imageURL
        pixelSize = imageURL.flatMap(pixelSizeOf) ?? capture.pixelSize
    }

    /// The file Copy, Save, Quick Look, drag-out and the thumbnail use.
    var fileURL: URL { imageURL ?? capture.fileURL }
    /// Export and drag file name (without extension): always the capture's.
    var exportName: String { capture.displayName }
    var isAnnotated: Bool { imageURL != nil }

    var caption: String { "\(Int(pixelSize.width)) × \(Int(pixelSize.height))" }

    static func headerPixelSize(_ url: URL) -> CGSize? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let w = props[kCGImagePropertyPixelWidth] as? Int, let h = props[kCGImagePropertyPixelHeight] as? Int
        else { return nil }
        return CGSize(width: w, height: h)
    }
}
