import CoreGraphics
import Foundation
import ImageIO
import Synchronization

/// Supplies the decoded base image and caches redaction results by
/// (rect, mode, strength). Thread-safe: state is behind a `Mutex`.
public final class BaseImageProvider: Sendable {
    public struct RedactionKey: Hashable, Sendable {
        public var rect: CGRect
        public var mode: RedactMode
    }

    public let url: URL
    private let state: Mutex<State>

    private struct State: @unchecked Sendable {
        // CGImage is immutable and thread-safe; it is only stored and handed out here.
        var image: CGImage?
        var redactions: [RedactionKey: CGImage] = [:]
    }

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

    /// Redacted pixels for `rect` (base-image pixels, top-left origin), cached.
    /// TODO(engineer C): implement pixelate/blur with Core Image. Returns nil for now.
    public func redactedImage(rect: CGRect, mode: RedactMode) -> CGImage? {
        let key = RedactionKey(rect: rect, mode: mode)
        return state.withLock { $0.redactions[key] }
    }

    public func clearCache() {
        state.withLock { $0.redactions.removeAll() }
    }
}
