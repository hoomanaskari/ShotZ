import AppKit
import ImageIO
import ShotzCore

/// Small downsampled thumbnails for the history submenu. Decoding happens
/// off the main actor; results are cached by capture id.
@MainActor final class HistoryThumbnails {
    private var cache: [CaptureResult.ID: NSImage] = [:]
    private var inFlight: Set<CaptureResult.ID> = []
    /// Menu thumbnails are drawn at this height (points).
    nonisolated static let height: CGFloat = 32

    func image(for id: CaptureResult.ID) -> NSImage? { cache[id] }

    /// Loads any missing thumbnails, calling `ready` on the main actor as
    /// each arrives. Drops cache entries no longer listed.
    func load(_ captures: [CaptureResult], ready: @escaping @MainActor (CaptureResult.ID) -> Void) {
        let ids = Set(captures.map(\.id))
        cache = cache.filter { ids.contains($0.key) }
        for capture in captures where cache[capture.id] == nil && !inFlight.contains(capture.id) {
            inFlight.insert(capture.id)
            let url = capture.fileURL
            let id = capture.id
            Task.detached(priority: .utility) {
                let cg = Self.decode(url, maxPixel: Int(Self.height * 2 * 2))
                await MainActor.run {
                    self.inFlight.remove(id)
                    guard let cg else { return }
                    let aspect = CGFloat(cg.width) / CGFloat(max(cg.height, 1))
                    let w = min(max(Self.height * aspect, Self.height * 0.6), Self.height * 2)
                    self.cache[id] = NSImage(cgImage: cg, size: NSSize(width: w, height: Self.height))
                    ready(id)
                }
            }
        }
    }

    nonisolated static func decode(_ url: URL, maxPixel: Int) -> CGImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            return nil
        }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(src, 0, options as CFDictionary)
    }
}
