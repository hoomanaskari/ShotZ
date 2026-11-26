import AnnotationKit
import AppKit
import Testing
@testable import AnnotationEditor

@MainActor
struct GlyphSheetTests {
    static let all: [EditorGlyph] = [.select, .arrow, .rectangle, .ellipse, .line, .text, .highlighter, .redact, .counter, .pen, .crop,
                                     .background, .copy, .save, .drag, .more, .eyedropper, .bold, .highlightFreehand, .highlightRect,
                                     .opacity, .cornerRadius, .strength, .angle, .padding]
        + ArrowStyle.allCases.map { .arrowStyle($0) }
        + ObjectStyle.FillMode.allCases.map { .fill($0, ellipse: false) } + [.fill(.outline, ellipse: true), .fill(.filled, ellipse: true)]
        + ObjectStyle.Dash.allCases.map { .dash($0) } + TextStyle.Decoration.allCases.map { .textDecoration($0) }
        + TextStyle.Alignment.allCases.map { .textAlign($0) } + RedactMode.Kind.allCases.map { .redactMode($0) }
        + (0..<5).map { .thickness($0) }

    /// Every glyph renders a non-empty template image. With SHOTZ_GLYPH_SHEET=<png> it also
    /// writes a contact sheet for review.
    @Test func everyGlyphDraws() throws {
        let size: CGFloat = 40, cols = 10
        let rows = (Self.all.count + cols - 1) / cols
        let sheet = NSImage(size: NSSize(width: CGFloat(cols) * 56, height: CGFloat(rows) * 56), flipped: true) { _ in
            for (i, g) in Self.all.enumerated() {
                let img = EditorGlyphs.image(g, size: size)
                #expect(img.isTemplate)
                let r = NSRect(x: CGFloat(i % cols) * 56 + 8, y: CGFloat(i / cols) * 56 + 8, width: size, height: size)
                NSColor.labelColor.set()
                img.draw(in: r)
                r.fill(using: .sourceAtop)
            }
            return true
        }
        let tiff = try #require(sheet.tiffRepresentation)
        let rep = try #require(NSBitmapImageRep(data: tiff))
        if let path = ProcessInfo.processInfo.environment["SHOTZ_GLYPH_SHEET"] {
            try rep.representation(using: .png, properties: [:])?.write(to: URL(filePath: path))
        }
    }
}

@MainActor
struct GlyphSegmentedControlTests {
    private func control() -> (GlyphSegmentedControl, () -> [Int]) {
        var picked: [Int] = []
        let segments = ["One", "Two", "Three"].map {
            GlyphSegmentedControl.Segment(image: EditorGlyphs.image(.arrow), title: nil, label: $0, shortcut: "X")
        }
        let c = GlyphSegmentedControl(style: .options, segments: segments, selected: 0, label: "Pick")
        c.onSelect = { picked.append($0) }
        return (c, { picked })
    }

    @Test func eachSegmentIsAVoiceOverRadioButton() throws {
        let (c, picked) = control()
        let children = try #require(c.accessibilityChildren() as? [NSAccessibilityElement])
        #expect(children.count == 3)
        #expect(children.map { $0.accessibilityLabel() } == ["One", "Two", "Three"])
        #expect(children.map { $0.accessibilityRole() } == Array(repeating: .radioButton, count: 3))
        #expect(children[0].accessibilityValue() as? Int == 1)
        #expect(children[2].accessibilityPerformPress())
        #expect(picked() == [2])
        #expect(c.selectedIndex == 2)
        #expect(children[2].accessibilityValue() as? Int == 1)
        #expect(c.accessibilityRole() == .radioGroup)
    }

    @Test func arrowKeysMoveTheSelectionAndGroupsAddSpace() throws {
        let (c, picked) = control()
        let right = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 124))
        c.keyDown(with: right)
        c.keyDown(with: right)
        c.keyDown(with: right)
        #expect(picked() == [1, 2, 2]) // stops at the end
        let plain = c.intrinsicContentSize.width
        c.groupStarts = [1]
        #expect(c.intrinsicContentSize.width > plain)
        #expect(c.intrinsicContentSize.height == EditorMetrics.optionHeight)
    }
}
