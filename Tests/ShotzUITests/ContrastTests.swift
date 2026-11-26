import AppKit
import Testing
@testable import ShotzUI

/// WCAG 2 contrast: text on its fill ≥ 4.5:1, icons ≥ 3:1, in every appearance and for a range
/// of system accent colours.
@MainActor
@Suite(.serialized)
struct ContrastTests {
    typealias P = ShotzUI.Palette
    var currentHC = false
    /// (name, appearance, increased contrast)
    static var appearances: [(String, NSAppearance, Bool)] {
        [("light", .init(named: .aqua)!, false), ("dark", .init(named: .darkAqua)!, false),
         ("light-hc", .init(named: .aqua)!, true), ("dark-hc", .init(named: .darkAqua)!, true)]
    }
    static let accents: [(String, NSColor)] = [
        ("blue", NSColor(srgbRed: 0, green: 0.478, blue: 1, alpha: 1)), ("purple", NSColor(srgbRed: 0.58, green: 0.33, blue: 0.80, alpha: 1)),
        ("pink", NSColor(srgbRed: 0.97, green: 0.31, blue: 0.62, alpha: 1)), ("red", NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)),
        ("orange", NSColor(srgbRed: 0.97, green: 0.51, blue: 0.10, alpha: 1)), ("yellow", NSColor(srgbRed: 1, green: 0.78, blue: 0, alpha: 1)),
        ("green", NSColor(srgbRed: 0.38, green: 0.73, blue: 0.27, alpha: 1)), ("graphite", NSColor(srgbRed: 0.55, green: 0.55, blue: 0.57, alpha: 1)),
    ]

    func on(_ fg: NSColor, _ bg: NSColor, over base: NSColor? = nil, in a: NSAppearance) -> CGFloat {
        P.increasedContrastOverride = currentHC
        var back = bg.resolved(in: a)
        if let base { back = back.composited(over: base.resolved(in: a)) } else if back.alphaComponent < 1 { back = back.composited(over: P.windowBackground.resolved(in: a)) }
        return P.contrast(fg.resolved(in: a).composited(over: back), back)
    }

    @Test mutating func textOnSurfaces() {
        defer { P.increasedContrastOverride = false }
        for (name, a, hc) in Self.appearances {
            currentHC = hc
            for (bgName, bg) in [("window", P.windowBackground), ("surface", P.surface), ("raised", P.raised)] {
                #expect(on(P.textPrimary, bg, in: a) >= 7, "\(name) primary on \(bgName)")
                #expect(on(P.textSecondary, bg, in: a) >= 4.5, "\(name) secondary on \(bgName): \(on(P.textSecondary, bg, in: a))")
                #expect(on(P.danger, bg, in: a) >= 4.5, "\(name) danger on \(bgName): \(on(P.danger, bg, in: a))")
            }
            #expect(on(P.textSecondary, P.surfaceSunken, over: P.windowBackground, in: a) >= 4.5, "\(name) secondary on sunken")
            #expect(on(P.success, P.surface, in: a) >= 4.5, "\(name) success")
            #expect(on(P.warning, P.surface, in: a) >= 4.5, "\(name) warning")
            // Glass over the worst case (a white image): white text still reads.
            #expect(on(P.glassContent, P.glassFill, over: .white, in: a) >= 4.5, "\(name) glass")
        }
    }

    @Test mutating func accentFamilyForEveryAccent() {
        defer { P.accentOverride = nil; P.increasedContrastOverride = false }
        for (accentName, accent) in Self.accents {
            P.accentOverride = accent
            for (name, a, hc) in Self.appearances {
            currentHC = hc
                let ctx = "\(accentName)/\(name)"
                #expect(on(P.onAccent, P.accentFill, in: a) >= 4.5, "\(ctx) primary label: \(on(P.onAccent, P.accentFill, in: a))")
                for (bgName, bg) in [("window", P.windowBackground), ("surface", P.surface)] {
                    // Chip labels are text on the selected tint; tool glyphs are icons.
                    let c = on(P.selectedContent, P.selectedFill, over: bg, in: a)
                    #expect(c >= 4.5, "\(ctx) selected text on \(bgName): \(c)")
                }
            }
        }
    }

    @Test mutating func glyphsOnInteractionFills() {
        defer { P.increasedContrastOverride = false }
        for (name, a, hc) in Self.appearances {
            currentHC = hc
            for fill in [P.fillHover, P.fillPressed] {
                #expect(on(P.textPrimary, fill, over: P.surface, in: a) >= 4.5, "\(name)")
                #expect(on(P.textSecondary, fill, over: P.surface, in: a) >= 3, "\(name) secondary glyph")
            }
        }
    }
}
