import UniformTypeIdentifiers

public enum ImageFormat: String, Codable, Sendable, CaseIterable, Hashable {
    case png, jpeg, heic

    public var fileExtension: String {
        switch self {
        case .png: "png"
        case .jpeg: "jpg"
        case .heic: "heic"
        }
    }

    public var utType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }
}
