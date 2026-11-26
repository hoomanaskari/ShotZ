import AnnotationKit
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import AnnotationEditor

struct ShapeTranslationTests {
    @Test func detectsPureMoves() {
        let a = AnnotationObject(shape: .rectangle(CGRect(x: 0, y: 0, width: 10, height: 10), cornerRadius: 2))
        var b = a
        b.shape = a.shape.offset(by: CGVector(dx: 5, dy: -3))
        #expect(ShapeTranslation.delta(from: a, to: b) == CGVector(dx: 5, dy: -3))
        var c = a
        c.shape = .rectangle(CGRect(x: 0, y: 0, width: 11, height: 10), cornerRadius: 2)
        #expect(ShapeTranslation.delta(from: a, to: c) == nil)
        var d = b
        d.style.color = .blue
        #expect(ShapeTranslation.delta(from: a, to: d) == nil)
    }

    @Test func penAndArrowMoves() {
        let pen = AnnotationObject(shape: .pen([CGPoint(x: 0, y: 0), CGPoint(x: 5, y: 9)]))
        #expect(ShapeTranslation.delta(from: pen, to: AnnotationObject(id: pen.id, shape: pen.shape.offset(by: CGVector(dx: 1, dy: 1)))) == CGVector(dx: 1, dy: 1))
        let arrow = AnnotationObject(shape: .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 5), style: .curved)))
        var bent = arrow
        bent.shape = .arrow(ArrowGeometry(start: .zero, end: CGPoint(x: 10, y: 0), control: CGPoint(x: 5, y: 8), style: .curved))
        #expect(ShapeTranslation.delta(from: arrow, to: bent) == nil)
    }

    @Test func redactionsAlwaysRerender() {
        let a = AnnotationObject(shape: .redact(CGRect(x: 0, y: 0, width: 10, height: 10), .pixelate))
        let b = AnnotationObject(id: a.id, shape: a.shape.offset(by: CGVector(dx: 1, dy: 0)))
        #expect(ShapeTranslation.delta(from: a, to: b) == nil)
    }
}

struct CanvasLayoutTests {
    private let doc = AnnotationDocument(baseImageURL: URL(filePath: "/tmp/x.png"), pixelSize: CGSize(width: 1000, height: 500))

    @Test func plainAndCropped() {
        let plain = CanvasLayout.make(document: doc, editingCrop: false)
        #expect(plain.extent == CGSize(width: 1000, height: 500))
        var cropped = doc
        cropped.crop = CGRect(x: 100, y: 50, width: 400, height: 200)
        let l = CanvasLayout.make(document: cropped, editingCrop: false)
        #expect(l.extent == CGSize(width: 400, height: 200))
        #expect(l.toCanvas(CGPoint(x: 100, y: 50)) == .zero)
        #expect(l.toImage(.zero) == CGPoint(x: 100, y: 50))
        // The crop tool shows the whole image.
        #expect(CanvasLayout.make(document: cropped, editingCrop: true).extent == CGSize(width: 1000, height: 500))
    }

    @Test func backgroundMatchesAnnotationKitLayout() {
        var d = doc
        d.background = BackgroundStyle(padding: 0.1, aspect: .square)
        let l = CanvasLayout.make(document: d, editingCrop: false)
        let kit = BackgroundLayout(document: d)
        #expect(l.extent == kit.canvasSize)
        #expect(l.imageFrame == kit.imageFrame)
        #expect(l.extent.width == l.extent.height)
        #expect(l.toCanvas(.zero) == kit.imageFrame.origin)
    }
}

@MainActor
struct PasteboardPlacementTests {
    private let doc = AnnotationDocument(baseImageURL: URL(filePath: "/tmp/x.png"), pixelSize: CGSize(width: 1000, height: 500))

    @Test func offsetsCopiesOnTopOfOriginals() {
        var d = doc
        let r = AnnotationObject(shape: .rectangle(CGRect(x: 10, y: 10, width: 50, height: 50), cornerRadius: 0))
        d.objects = [r]
        let offset = ObjectPasteboard.placementOffset(for: [r], in: d, step: 12)
        #expect(offset == CGVector(dx: 12, dy: 12))
        #expect(ObjectPasteboard.placementOffset(for: [r], in: doc, step: 12) == .zero)
    }

    @Test func bringsFarAwayObjectsIntoView() {
        let r = AnnotationObject(shape: .rectangle(CGRect(x: 4000, y: 3000, width: 100, height: 100), cornerRadius: 0))
        let offset = ObjectPasteboard.placementOffset(for: [r], in: doc, step: 12)
        let moved = CGRect(x: 4000, y: 3000, width: 100, height: 100).offsetBy(dx: offset.dx, dy: offset.dy)
        #expect(doc.imageRect.contains(CGPoint(x: moved.midX, y: moved.midY)))
    }
}

@MainActor
struct BackgroundPresetTests {
    @Test func saveReplaceDeleteAndLast() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        let p = BackgroundPresets(defaults: defaults)
        #expect(p.last == BackgroundPresets.defaultStyle)
        var s = BackgroundStyle(padding: 0.2)
        p.save(s, name: "Deck")
        s.padding = 0.05
        p.save(s, name: " Deck ")
        #expect(p.saved.count == 1)
        #expect(p.saved.first?.style.padding == 0.05)
        p.last = s
        #expect(BackgroundPresets(defaults: defaults).last == s)
        p.delete(name: "Deck")
        #expect(p.saved.isEmpty)
        #expect(BackgroundPresets.gradients.count == 12)
    }

    @Test func backgroundChangesAreUndoable() {
        let m = makeModel()
        m.setBackground(BackgroundStyle(), interactive: true)
        m.setBackground(BackgroundStyle(padding: 0.2), interactive: true)
        m.store.commitInteractiveChange()
        #expect(m.document.background?.padding == 0.2)
        m.store.undo()
        #expect(m.document.background == nil) // the whole slider drag was one step
    }
}

@MainActor
struct CoordinatorTests {
    @Test func imageInfoReadsSizeAndScale() throws {
        let dir = FileManager.default.temporaryDirectory.appending(path: "ShotzEditorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) } // best-effort cleanup
        let url = dir.appending(path: "x.png")
        let ctx = try #require(CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        let image = try #require(ctx.makeImage())
        let dest = try #require(CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, [kCGImagePropertyDPIWidth: 144, kCGImagePropertyDPIHeight: 144] as CFDictionary)
        #expect(CGImageDestinationFinalize(dest))
        let info = try #require(EditorCoordinator.imageInfo(url))
        #expect(info.pixelSize == CGSize(width: 40, height: 20))
        #expect(info.scale == 2)
    }
}
