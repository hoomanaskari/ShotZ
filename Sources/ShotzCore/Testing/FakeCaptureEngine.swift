import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A `CaptureEngine` for tests in any module. Writes a small solid PNG into
/// `options.destinationDirectory` (or returns/throws a scripted outcome).
public actor FakeCaptureEngine: CaptureEngine {
    public enum Outcome: Sendable {
        case image(width: Int, height: Int)
        case cancel
        case fail(CaptureError)
    }

    public private(set) var requestedModes: [CaptureMode] = []
    private var outcomes: [Outcome]
    private let fallback: Outcome

    /// Outcomes are consumed in order; `fallback` is used once they run out.
    public init(outcomes: [Outcome] = [], fallback: Outcome = .image(width: 40, height: 30)) {
        self.outcomes = outcomes
        self.fallback = fallback
    }

    public func enqueue(_ outcome: Outcome) { outcomes.append(outcome) }

    public func capture(_ mode: CaptureMode, options: CaptureOptions) async throws -> CaptureResult? {
        requestedModes.append(mode)
        let outcome = outcomes.isEmpty ? fallback : outcomes.removeFirst()
        switch outcome {
        case .cancel:
            return nil
        case .fail(let error):
            throw error
        case .image(let width, let height):
            try FileManager.default.createDirectory(at: options.destinationDirectory, withIntermediateDirectories: true)
            let now = Date()
            let name = FileNaming.format(options.fileNamePattern, date: now)
            let url = FileNaming.uniqueURL(in: options.destinationDirectory, base: name, ext: "png")
            try Self.writePNG(width: width, height: height, to: url)
            let kind: CaptureKind = switch mode {
            case .fullscreen: .fullscreen
            case .window: .window
            case .area, .allInOne: .area
            }
            return CaptureResult(
                fileURL: url,
                displayName: url.deletingPathExtension().lastPathComponent,
                kind: kind,
                pixelSize: CGSize(width: width, height: height),
                scale: 1,
                displayID: CGMainDisplayID(),
                createdAt: now
            )
        }
    }

    /// Writes a solid-colour PNG. Useful as a fixture in other tests too.
    public static func writePNG(width: Int, height: Int, to url: URL) throws {
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { throw CaptureError.failed("context") }
        ctx.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else { throw CaptureError.failed("png") }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else { throw CaptureError.failed("png finalize") }
    }
}
