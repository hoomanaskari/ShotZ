import CryptoKit
import Foundation
import ShotzCore

/// Stable capture ids for `--debug-edit-capture`: the same source image maps
/// to the same history entry on every launch, so a second launch reopens the
/// same capture (and its editor document and recorded export).
public enum DebugCaptureIdentity {
    /// A name-based UUID (SHA-256 of the standardized absolute path, version
    /// and variant bits set as for RFC 4122 name-based ids).
    public static func id(forSourcePath url: URL) -> UUID {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        var bytes = Array(SHA256.hash(data: Data("shotz.debug-capture:\(path)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50   // version 5 layout
        bytes[8] = (bytes[8] & 0x3F) | 0x80   // RFC 4122 variant
        return UUID(uuid: (bytes[0], bytes[1], bytes[2], bytes[3], bytes[4], bytes[5], bytes[6], bytes[7],
                           bytes[8], bytes[9], bytes[10], bytes[11], bytes[12], bytes[13], bytes[14], bytes[15]))
    }
}

extension FileHistoryStore {
    /// The capture with this id if it is in history and its image still
    /// exists; nil means "import it (again)".
    public func reusableCapture(id: CaptureResult.ID) -> CaptureResult? {
        guard let capture = entry(id: id)?.capture,
              FileManager.default.fileExists(atPath: capture.fileURL.path(percentEncoded: false)) else { return nil }
        return capture
    }
}
