import AppKit
import ImageIO
import ShotzCore
import UniformTypeIdentifiers

/// Records delegate calls during the self-test (no editor opens, nothing is
/// deleted from history).
@MainActor final class RecordingQuickAccessDelegate: QuickAccessDelegate {
    private(set) var annotated: [CaptureResult] = []
    private(set) var closed: [(id: UUID, deleteFile: Bool)] = []

    func quickAccess(requestAnnotate capture: CaptureResult) { annotated.append(capture) }
    func quickAccess(didClose capture: CaptureResult, deleteFile: Bool) { closed.append((capture.id, deleteFile)) }
    func quickAccess(didExport capture: CaptureResult, to url: URL) {}
}

/// SPEC §4.4 Annotate / §4.6 returning from the editor, driven by direct calls.
extension StackSelfTest {
    func returnFromEditor(template: CaptureResult, qa: QuickAccessController, dir: URL) async {
        let recorder = RecordingQuickAccessDelegate()
        let realDelegate = qa.delegate
        qa.delegate = recorder
        defer { qa.delegate = realDelegate }

        let capture = CaptureResult(fileURL: template.fileURL, displayName: "Return test", kind: template.kind,
                                    pixelSize: template.pixelSize, scale: template.scale, displayID: template.displayID)
        qa.present(capture)
        await wait(450)
        guard let first = qa.cards[capture.id] else { return check("return: card presented", false) }
        let liveBefore = qa.cards.count

        qa.perform(.annotate, on: first)
        await wait(300)
        check("annotate hides the card", qa.cards[capture.id] == nil && !qa.model.contains(capture.id))
        check("annotate is not a close (no restore entry, no delete)", recorder.closed.isEmpty && recorder.annotated.map(\.id) == [capture.id])

        let annotated = dir.appending(path: "annotated.png")
        Self.writeSolidPNG(width: 1200, height: 900, red: 1, green: 0, blue: 1, to: annotated)
        qa.present(capture, imageURL: annotated)
        await wait(500)
        guard let back = qa.cards[capture.id] else { return check("return: card back", false) }
        check("returning card is the newest (bottom)", qa.model.order.last == capture.id && visibleNewestFirst.first === back)
        check("returning card shows the annotated size", back.source.caption == "1200 × 900", back.source.caption)
        check("thumbnail comes from the annotated image", back.thumbnailCenterIsMagenta())
        check("Copy/Save/Quick Look use the annotated file", back.source.fileURL == annotated && back.source.exportName == "Return test")
        if let writer = qa.cardDragWriter(back) as? DragFileWriter {
            let same = FileManager.default.contentsEqual(atPath: writer.fileURL.path(percentEncoded: false), andPath: annotated.path(percentEncoded: false))
            check("drag delivers the annotated image under the capture's name", same && writer.fileURL.deletingPathExtension().lastPathComponent == "Return test",
                  writer.fileURL.lastPathComponent)
            qa.card(back, dragEndedWith: [], swiped: false) // cancelled: keeps the card
        } else {
            check("drag writer for annotated card", false)
        }

        // Editor saved again: same path rewritten with different pixels.
        Self.writeSolidPNG(width: 1000, height: 1000, red: 0, green: 0.8, blue: 0.2, to: annotated)
        qa.present(capture, imageURL: annotated)
        await wait(500)
        let again = qa.cards[capture.id]
        let liveWithID = (again?.superview?.subviews ?? []).compactMap { $0 as? CardView }.filter { $0.capture.id == capture.id && !$0.isExiting }
        check("re-present replaces, never duplicates", liveWithID.count == 1 && qa.cards.count == liveBefore)
        check("rewritten file at the same path refreshes thumbnail and caption",
              again?.thumbnailCenterIsMagenta() == false && again?.source.caption == "1000 × 1000")

        if let again {
            qa.perform(.annotate, on: again)
            check("Annotate on the annotated card reopens the original capture", recorder.annotated.last == capture)
        }
        for _ in 0..<10 { // rapid open/close cycles
            if let c = qa.cards[capture.id] { qa.perform(.annotate, on: c) }
            qa.present(capture, imageURL: annotated)
        }
        await wait(700)
        let live = qa.cards.values.filter { !$0.isExiting }
        let ids = live.map(\.capture.id)
        check("rapid annotate/return cycles keep exactly one card", ids.filter { $0 == capture.id }.count == 1 && live.count == liveBefore && recorder.closed.isEmpty)
        checkOrder("order after return cycles")
        if let c = qa.cards[capture.id] { qa.remove(c, animation: .none) }
    }

    static func writeSolidPNG(width: Int, height: Int, red: CGFloat, green: CGFloat, blue: CGFloat, to url: URL) {
        guard let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return }
        ctx.setFillColor(CGColor(srgbRed: red, green: green, blue: blue, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = ctx.makeImage(),
              let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }
}

extension CardView {
    /// Self-test probe: is the thumbnail's centre pixel magenta?
    func thumbnailCenterIsMagenta() -> Bool {
        guard let image = thumbnailImage,
              let ctx = CGContext(data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let data = ctx.data else { return false }
        ctx.draw(image, in: CGRect(x: -CGFloat(image.width / 2), y: -CGFloat(image.height / 2), width: CGFloat(image.width), height: CGFloat(image.height)))
        let px = data.bindMemory(to: UInt8.self, capacity: 4)
        return px[0] > 200 && px[1] < 70 && px[2] > 200
    }
}
