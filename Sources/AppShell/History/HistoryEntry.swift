import Foundation
import ShotzCore

/// One row of the history index (SPEC §6): the capture plus what happened to it.
public struct HistoryEntry: Codable, Sendable, Hashable, Identifiable {
    public var capture: CaptureResult
    /// Last export written for this capture (Save / auto-save), if any.
    public var exportURL: URL?

    public var id: CaptureResult.ID { capture.id }

    public init(capture: CaptureResult, exportURL: URL? = nil) {
        self.capture = capture
        self.exportURL = exportURL
    }
}

/// On-disk index format. Versioned so later phases can migrate it.
struct HistoryIndexFile: Codable {
    static let currentVersion = 1

    var version: Int
    var entries: [HistoryEntry]

    init(entries: [HistoryEntry]) {
        self.version = Self.currentVersion
        self.entries = entries
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decodeIfPresent(Int.self, forKey: .version) ?? Self.currentVersion
        // Decode entry by entry so one bad row does not lose the whole index.
        entries = try c.decode([Lenient<HistoryEntry>].self, forKey: .entries).compactMap(\.value)
    }
}

/// Decodes `T` or yields nil instead of failing the surrounding array.
struct Lenient<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        // A malformed element is genuinely skippable; the caller logs the count.
        value = try? T(from: decoder)
    }
}

/// ISO 8601 with fractional seconds (so captures taken within one second keep
/// their order and compare equal after a reload); plain ISO 8601 still reads.
enum HistoryDates {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var c = encoder.singleValueContainer()
            try c.encode(Date.ISO8601FormatStyle(includingFractionalSeconds: true).format(date))
        }
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let c = try decoder.singleValueContainer()
            let string = try c.decode(String.self)
            let fractional = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
            if let date = try? fractional.parse(string) { return date }
            if let date = try? Date.ISO8601FormatStyle().parse(string) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: "Bad date \(string)")
        }
        return decoder
    }
}
