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

    /// Written into every saved document. Bump when the format changes incompatibly;
    /// decoding stays tolerant of older and newer versions.
    public static let formatVersion = 1

    enum CodingKeys: String, CodingKey {
        case version, baseImageURL, pixelSize, scale, objects, crop, background
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        baseImageURL = try c.decode(URL.self, forKey: .baseImageURL)
        pixelSize = try c.decode(CGSize.self, forKey: .pixelSize)
        scale = (try? c.decodeIfPresent(CGFloat.self, forKey: .scale)) ?? 1 // missing/bad scale: assume 1×
        objects = (try? c.decodeIfPresent(LossyArray<AnnotationObject>.self, forKey: .objects))?.elements ?? []
        crop = try? c.decodeIfPresent(CGRect.self, forKey: .crop) // a damaged crop falls back to the full image
        background = try? c.decodeIfPresent(BackgroundStyle.self, forKey: .background) // damaged: background off
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Self.formatVersion, forKey: .version)
        try c.encode(baseImageURL, forKey: .baseImageURL)
        try c.encode(pixelSize, forKey: .pixelSize)
        try c.encode(scale, forKey: .scale)
        try c.encode(objects, forKey: .objects)
        try c.encodeIfPresent(crop, forKey: .crop)
        try c.encodeIfPresent(background, forKey: .background)
    }

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
