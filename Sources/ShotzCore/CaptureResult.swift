import CoreGraphics
import Foundation

/// What every capture hands downstream. The PNG at `fileURL` is the source of truth.
public struct CaptureResult: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    /// Lossless PNG in the private captures folder.
    public let fileURL: URL
    /// e.g. "ShotZ 2026-11-26 at 10.42.07".
    public let displayName: String
    public let kind: CaptureKind
    /// Native pixels.
    public let pixelSize: CGSize
    /// 2.0 on Retina.
    public let scale: CGFloat
    /// `CGDirectDisplayID` the capture came from.
    public let displayID: UInt32
    public let createdAt: Date

    public init(
        id: UUID = UUID(),
        fileURL: URL,
        displayName: String,
        kind: CaptureKind,
        pixelSize: CGSize,
        scale: CGFloat,
        displayID: UInt32,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileURL = fileURL
        self.displayName = displayName
        self.kind = kind
        self.pixelSize = pixelSize
        self.scale = scale
        self.displayID = displayID
        self.createdAt = createdAt
    }
}

extension CaptureResult {
    /// The same capture, placed on another display (e.g. a card returning
    /// from an editor window on that display). Identity is unchanged.
    public func onDisplay(_ displayID: UInt32) -> CaptureResult {
        CaptureResult(id: id, fileURL: fileURL, displayName: displayName, kind: kind,
                      pixelSize: pixelSize, scale: scale, displayID: displayID, createdAt: createdAt)
    }
}
