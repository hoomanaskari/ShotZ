import CoreGraphics
import Foundation
import ImageIO
import ShotzCore

/// Turns an existing image into a `CaptureResult` in the captures folder,
/// for `--debug-present`. Kind area, scale 2, main display.
enum DebugCaptureImporter {
    enum ImportError: Error { case unreadable(String) }

    static func importImage(at source: URL, options: CaptureOptions) throws -> CaptureResult {
        guard let src = CGImageSourceCreateWithURL(source as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int
        else { throw ImportError.unreadable(source.path(percentEncoded: false)) }

        let fm = FileManager.default
        try fm.createDirectory(at: options.destinationDirectory, withIntermediateDirectories: true)
        let now = Date()
        let name = FileNaming.format(options.fileNamePattern, date: now)
        let ext = source.pathExtension.isEmpty ? "png" : source.pathExtension.lowercased()
        let destination = FileNaming.uniqueURL(in: options.destinationDirectory, base: name, ext: ext)
        try fm.copyItem(at: source, to: destination)
        return CaptureResult(
            fileURL: destination,
            displayName: destination.deletingPathExtension().lastPathComponent,
            kind: .area,
            pixelSize: CGSize(width: width, height: height),
            scale: 2,
            displayID: CGMainDisplayID(),
            createdAt: now
        )
    }
}
