import AnnotationKit
import ShotzCore
import Testing
@testable import AnnotationEditor

struct EditorGlyphMappingTests {
    static let all: [EditorGlyph] = [.select, .arrow, .rectangle, .ellipse, .line, .text, .highlighter, .redact, .counter, .pen, .crop,
                                     .background, .copy, .save, .drag, .more, .zoomIn, .zoomOut, .bold, .highlightFreehand, .highlightRect,
                                     .opacity, .cornerRadius, .padding, .eyedropper, .strength, .angle]
        + ArrowStyle.allCases.map { .arrowStyle($0) }
        + ObjectStyle.FillMode.allCases.map { .fill($0, ellipse: false) }
        + ObjectStyle.Dash.allCases.map { .dash($0) } + TextStyle.Decoration.allCases.map { .textDecoration($0) }
        + TextStyle.Alignment.allCases.map { .textAlign($0) } + RedactMode.Kind.allCases.map { .redactMode($0) }
        + (0..<5).map { .thickness($0) }

    /// Every chrome icon comes from the shared set.
    @Test func everyGlyphMapsToTheSharedSet() {
        for g in Self.all { #expect(EditorGlyphs.shotzIcon(g) != nil, "\(g)") }
        #expect(EditorGlyphs.shotzIcon(.eyedropper) == .eyedropper)
        #expect(EditorGlyphs.shotzIcon(.thickness(4)) == .thickness5)
        #expect(EditorGlyphs.shotzIcon(.tool(.redact)) == .redact)
    }
}
