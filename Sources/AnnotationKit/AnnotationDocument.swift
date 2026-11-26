import CoreGraphics
import Foundation

/// Value-type document. All geometry is in base-image pixel space, origin top-left.
public struct AnnotationDocument: Codable, Sendable, Equatable {
    public var baseImageURL: URL
    /// Base image size in pixels.
    public var pixelSize: CGSize
    public var scale: CGFloat
    /// z-order, back to front.
    public var objects: [AnnotationObject]
    /// nil = full image.
    public var crop: CGRect?
    /// nil = no background.
    public var background: BackgroundStyle?

    public init(
        baseImageURL: URL,
        pixelSize: CGSize,
        scale: CGFloat = 1,
        objects: [AnnotationObject] = [],
        crop: CGRect? = nil,
        background: BackgroundStyle? = nil
    ) {
        self.baseImageURL = baseImageURL
        self.pixelSize = pixelSize
        self.scale = scale
        self.objects = objects
        self.crop = crop
        self.background = background
    }

    /// The visible image rect (crop or full image).
    public var imageRect: CGRect {
        crop ?? CGRect(origin: .zero, size: pixelSize)
    }

    public func index(of id: AnnotationObject.ID) -> Int? {
        objects.firstIndex { $0.id == id }
    }

    public subscript(id id: AnnotationObject.ID) -> AnnotationObject? {
        get { index(of: id).map { objects[$0] } }
        set {
            guard let i = index(of: id) else { return }
            if let newValue { objects[i] = newValue } else { objects.remove(at: i) }
        }
    }

    // MARK: Persistence (JSON at HistoryStore.documentURL(for:))

    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func load(from url: URL) throws -> AnnotationDocument {
        try JSONDecoder().decode(AnnotationDocument.self, from: Data(contentsOf: url))
    }

    public func save(to url: URL) throws {
        try jsonData().write(to: url, options: .atomic)
    }
}
