import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Supplies the decoded base image and caches redaction results by
/// (rect, mode, strength, scale). Thread-safe: state is behind a `Mutex`.
/// Share one provider per open document between the editor and export so caches are reused.
public final class BaseImageProvider: Sendable {
    public struct RedactionKey: Hashable, Sendable {
        public var rect: CGRect
        public var mode: RedactMode
        /// Pixels per point of the document (block size and blur radius scale with it).
        public var scale: CGFloat = 1
    }

    public let url: URL
    private let state: Mutex<State>

    private struct State: @unchecked Sendable {
        // CGImage is immutable and thread-safe; it is only stored and handed out here.
        var image: CGImage?
        var preview: CGImage?
        var redactions: [RedactionKey: CGImage] = [:]
        /// Insertion order for a simple LRU bound on the cache.
        var order: [RedactionKey] = []
        var opaqueBounds: CGRect??
        var isOpaque: Bool?
    }

    /// Cached redaction bitmaps kept at most (each is at most the redact rect's size).
    static let cacheLimit = 48

    public init(url: URL) {
        self.url = url
        self.state = Mutex(State(image: nil))
    }

    /// For tests and in-memory images (e.g. New from Clipboard).
    public init(image: CGImage, url: URL) {
        self.url = url
        self.state = Mutex(State(image: image))
    }

    public enum LoadError: Error, Sendable { case unreadable(URL) }

    /// The full-resolution base image, decoded once.
    public func image() throws -> CGImage {
        if let cached = state.withLock({ $0.image }) { return cached }
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
              let img = CGImageSourceCreateImageAtIndex(src, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
        else { throw LoadError.unreadable(url) }
        state.withLock { $0.image = img }
        return img
    }

    /// A downsampled copy (long edge ≤ 1024 px) for cheap live redaction previews.
    public func previewImage() -> CGImage? {
        if let cached = state.withLock({ $0.preview }) { return cached }
        guard let full = try? image() else { return nil } // unreadable base: no preview, the caller draws nothing
        let longEdge = CGFloat(max(full.width, full.height))
        let k = min(1, 1024 / max(longEdge, 1))
        let w = max(Int(CGFloat(full.width) * k), 1), h = max(Int(CGFloat(full.height) * k), 1)
        guard let ctx = Redactor.bitmap(width: w, height: h, space: Redactor.workingSpace(of: full)) else { return nil }
        ctx.interpolationQuality = .medium
        ctx.draw(full, in: CGRect(x: 0, y: 0, width: w, height: h))
        let preview = ctx.makeImage()
        state.withLock { $0.preview = preview }
        return preview
    }

    /// Redacted pixels for `rect` (base-image pixels, top-left origin), computed from the base
    /// image only and cached. The rect is made integral and clipped to the image; returns nil
    /// for `.solid` (drawn as a fill), for an empty intersection, or if the image is unreadable.
    /// `scale` is the document's pixels-per-point; the renderer passes `document.scale`.
    public func redactedImage(rect: CGRect, mode: RedactMode, scale: CGFloat = 1) -> CGImage? {
        guard mode.kind != .solid, let full = try? image() else { return nil } // unreadable base: nothing to redact
        let clipped = Self.pixelRect(rect, imageSize: CGSize(width: full.width, height: full.height))
        guard !clipped.isEmpty else { return nil }
        let key = RedactionKey(rect: clipped, mode: mode, scale: scale)
        if let cached = state.withLock({ $0.redactions[key] }) { return cached }
        let result: CGImage?
        switch mode.kind {
        case .pixelate: result = Redactor.pixelate(full, rect: clipped, block: Redactor.blockSize(strength: mode.strength, scale: scale, rect: clipped))
        case .blur: result = Redactor.blur(full, rect: clipped, radius: Redactor.blurRadius(strength: mode.strength, scale: scale, rect: clipped))
        case .solid: result = nil
        }
        if let result {
            state.withLock { s in
                if s.redactions[key] == nil { s.order.append(key) }
                s.redactions[key] = result
                while s.order.count > Self.cacheLimit { s.redactions[s.order.removeFirst()] = nil }
            }
        }
        return result
    }

    /// Average relative luminance (0…1) of the base image inside `rect` (base-image pixels,
    /// top-left origin), sampled from the preview image. nil if unreadable or empty.
    public func averageLuminance(in rect: CGRect, imageSize: CGSize) -> CGFloat? {
        guard let preview = previewImage(), imageSize.width > 0 else { return nil }
        let k = CGFloat(preview.width) / imageSize.width
        let src = CGRect(x: rect.minX * k, y: rect.minY * k, width: rect.width * k, height: rect.height * k)
            .standardized.integral.intersection(CGRect(x: 0, y: 0, width: preview.width, height: preview.height))
        guard !src.isEmpty, let crop = preview.cropping(to: src),
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.interpolationQuality = .high
        ctx.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        let p = data.bindMemory(to: UInt8.self, capacity: 4)
        return RGBAColor(red: CGFloat(p[0]) / 255, green: CGFloat(p[1]) / 255, blue: CGFloat(p[2]) / 255).luminance
    }

    /// Integral rect clipped to the image, as used for cache keys and drawing.
    public static func pixelRect(_ rect: CGRect, imageSize: CGSize) -> CGRect {
        rect.standardized.integral.intersection(CGRect(origin: .zero, size: imageSize))
    }

    /// Bounding box of pixels with visible alpha (top-left origin), nil if fully opaque edges
    /// were never transparent or the image is unreadable. Used by background auto-balance so
    /// window captures with transparent shadow margins are centred by their visible content.
    public func visibleContentBounds() -> CGRect? {
        if let cached = state.withLock({ $0.opaqueBounds }) { return cached }
        let bounds = (try? image()).flatMap(Self.computeVisibleBounds) // unreadable base: no bounds
        state.withLock { $0.opaqueBounds = .some(bounds) }
        return bounds
    }

    /// True when every pixel is fully opaque (cached). Scans a downsampled alpha plane: any
    /// transparency, even a few pixels such as a window's rounded corner, lowers a sample below 255.
    public func isOpaque() -> Bool {
        if let cached = state.withLock({ $0.isOpaque }) { return cached }
        let result = (try? image()).map(Self.computeIsOpaque) ?? false // unreadable base: assume not opaque
        state.withLock { $0.isOpaque = result }
        return result
    }

    private static func computeIsOpaque(_ image: CGImage) -> Bool {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return true
        default: break
        }
        let k = min(1, 512 / CGFloat(max(image.width, image.height)))
        let w = max(Int(CGFloat(image.width) * k), 1), h = max(Int(CGFloat(image.height) * k), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return false }
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        for i in 0..<(w * h) where bytes[i * 4 + 3] < 255 { return false }
        return true
    }

    private static func computeVisibleBounds(_ image: CGImage) -> CGRect? {
        switch image.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast: return nil
        default: break
        }
        // Scan a downsampled alpha mask; precision of a few pixels is plenty for layout.
        let k = min(1, 512 / CGFloat(max(image.width, image.height)))
        let w = max(Int(CGFloat(image.width) * k), 1), h = max(Int(CGFloat(image.height) * k), 1)
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        let bytes = data.bindMemory(to: UInt8.self, capacity: w * h * 4)
        var minX = w, minY = h, maxX = -1, maxY = -1
        for y in 0..<h {
            for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 40 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= 0 else { return nil }
        // Memory rows are top-down for a bitmap context, matching top-left image space.
        let r = CGRect(x: CGFloat(minX) / k, y: CGFloat(minY) / k, width: CGFloat(maxX - minX + 1) / k, height: CGFloat(maxY - minY + 1) / k)
        let full = CGRect(x: 0, y: 0, width: image.width, height: image.height)
        let result = r.integral.intersection(full)
        return result == full ? nil : result
    }

    public func clearCache() {
        state.withLock {
            $0.redactions.removeAll()
            $0.order.removeAll()
        }
    }
}
