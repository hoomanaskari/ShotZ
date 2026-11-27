import CoreGraphics
import Foundation
import Testing
@testable import AnnotationKit

/// The background's 9-way position (SPEC §5.4 "inset alignment"): it places the image within the
/// padded canvas whenever there is room, with Auto and fixed aspects, auto-balance on or off.
struct BackgroundPositionTests {
    typealias A = BackgroundStyle.Alignment

    static func doc(_ size: CGSize = CGSize(width: 1000, height: 500), padding: CGFloat = 0.1,
                    aspect: BackgroundStyle.Aspect = .auto, alignment: A = .center, autoBalance: Bool = false) -> AnnotationDocument {
        var d = AnnotationDocument(baseImageURL: URL(filePath: "/x"), pixelSize: size)
        d.background = BackgroundStyle(padding: padding, autoBalance: autoBalance, alignment: alignment, aspect: aspect)
        return d
    }

    /// Horizontal and vertical direction of a cell: -1 leading, 0 centre, +1 trailing.
    static func direction(_ a: A) -> (x: Int, y: Int) {
        let x = [A.topLeft, .left, .bottomLeft].contains(a) ? -1 : [A.topRight, .right, .bottomRight].contains(a) ? 1 : 0
        let y = [A.topLeft, .top, .topRight].contains(a) ? -1 : [A.bottomLeft, .bottom, .bottomRight].contains(a) ? 1 : 0
        return (x, y)
    }

    @Test func centreIsUnchanged() {
        // The earlier arithmetic: free margin split evenly, rounded.
        for aspect in BackgroundStyle.Aspect.allCases {
            let d = Self.doc(aspect: aspect)
            let l = BackgroundLayout(document: d)
            #expect(l.imageFrame.minX == ((l.canvasSize.width - 1000) / 2).rounded(), "\(aspect)")
            #expect(l.imageFrame.minY == ((l.canvasSize.height - 500) / 2).rounded(), "\(aspect)")
        }
    }

    @Test(arguments: BackgroundStyle.Aspect.allCases)
    func everyCellMovesTheImageTheRightWay(_ aspect: BackgroundStyle.Aspect) {
        for autoBalance in [false, true] {
            let centre = BackgroundLayout(document: Self.doc(aspect: aspect, autoBalance: autoBalance)).imageFrame
            for a in A.allCases where a != .center {
                let l = BackgroundLayout(document: Self.doc(aspect: aspect, alignment: a, autoBalance: autoBalance))
                let d = Self.direction(a)
                let dx = l.imageFrame.minX - centre.minX, dy = l.imageFrame.minY - centre.minY
                #expect(d.x == 0 ? dx == 0 : (dx.sign == (d.x < 0 ? .minus : .plus) && dx != 0), "\(aspect) \(a) auto-balance \(autoBalance): dx \(dx)")
                #expect(d.y == 0 ? dy == 0 : (dy.sign == (d.y < 0 ? .minus : .plus) && dy != 0), "\(aspect) \(a) auto-balance \(autoBalance): dy \(dy)")
                // The chosen side keeps a quarter of the padding (100 → 25).
                if d.x < 0 { #expect(l.imageFrame.minX == 25) }
                if d.x > 0 { #expect(l.canvasSize.width - l.imageFrame.maxX == 25) }
                if d.y < 0 { #expect(l.imageFrame.minY == 25) }
                if d.y > 0 { #expect(l.canvasSize.height - l.imageFrame.maxY == 25) }
                #expect(l.canvasSize == BackgroundLayout(document: Self.doc(aspect: aspect, autoBalance: autoBalance)).canvasSize, "the canvas never changes size")
            }
        }
    }

    @Test func autoBalancePositionsTheVisibleContent() {
        // A window capture: 50 px of transparent shadow all round the 900 × 400 visible window.
        let visible = CGRect(x: 50, y: 50, width: 900, height: 400)
        let l = BackgroundLayout(document: Self.doc(alignment: .topLeft, autoBalance: true), visibleContent: visible)
        #expect(l.imageFrame.minX + visible.minX == 25 && l.imageFrame.minY + visible.minY == 25)
    }

    @Test func canPositionNeedsRoomAroundTheImage() {
        #expect(!BackgroundLayout.canPosition(Self.doc(padding: 0)))                   // no padding, Auto: nothing to move against
        #expect(BackgroundLayout.canPosition(Self.doc(padding: 0.1)))
        #expect(BackgroundLayout.canPosition(Self.doc(padding: 0, aspect: .square)))   // a fixed aspect leaves room
        var none = Self.doc(); none.background = nil
        #expect(!BackgroundLayout.canPosition(none))
    }

    @Test func noPaddingAutoAspectLeavesTheImageWhereItIs() {
        for a in A.allCases {
            #expect(BackgroundLayout(document: Self.doc(padding: 0, alignment: a)).imageFrame.origin == .zero, "\(a)")
        }
    }

    @Test func theRendererPutsTheImageWhereTheLayoutSays() throws {
        var d = Self.doc(CGSize(width: 400, height: 200), padding: 0.25, alignment: .topLeft)
        d.background?.fill = .solid(RGBAColor(red: 0, green: 1, blue: 0))
        d.background?.shadow = .off
        d.background?.cornerRadius = 0
        let base = BaseImageProvider(image: TestImages.base(width: 400, height: 200), url: d.baseImageURL)
        let out = try AnnotationRenderer.renderImage(d, base: base, outputScale: 1)
        let p = Pixels(out)
        // pad 100, the chosen (left/top) side keeps 25: image from (25, 25); fill to the right and below.
        #expect(p.rgba(10, 10) == [0, 255, 0, 255])
        #expect(p.rgba(40, 40) != [0, 255, 0, 255])
        #expect(p.rgba(out.width - 10, out.height - 10) == [0, 255, 0, 255])
        #expect(p.rgba(440, 240) == [0, 255, 0, 255])   // right of the image (it ends at 425)
    }
}
