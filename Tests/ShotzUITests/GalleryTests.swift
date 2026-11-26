import AppKit
import ShotzCore
import Testing
@testable import ShotzUI

/// SHOTZ_UI_GALLERY=<dir> [SHOTZ_UI_GALLERY_COPY=<dir>] swift test --filter GalleryTests
/// writes every control in every state, plus the compositions, light/dark at 1× and 2×.
@MainActor
@Suite(.serialized)
struct GalleryTests {
    init() { _ = NSApplication.shared }

    static let presetSwatches: [ShotzSwatchRow.Swatch] = [
        .init(NSColor(srgbRed: 0.93, green: 0.20, blue: 0.20, alpha: 1), name: "Red"),
        .init(NSColor(srgbRed: 0.98, green: 0.55, blue: 0.10, alpha: 1), name: "Orange"),
        .init(NSColor(srgbRed: 0.99, green: 0.83, blue: 0.10, alpha: 1), name: "Yellow"),
        .init(NSColor(srgbRed: 0.20, green: 0.72, blue: 0.33, alpha: 1), name: "Green"),
        .init(NSColor(srgbRed: 0.15, green: 0.48, blue: 0.96, alpha: 1), name: "Blue"),
        .init(NSColor(srgbRed: 0.58, green: 0.32, blue: 0.90, alpha: 1), name: "Purple"),
        .init(NSColor(srgbRed: 0.08, green: 0.08, blue: 0.09, alpha: 1), name: "Black"),
        .init(NSColor.white, name: "White"),
    ]

    static func states(_ make: () -> ShotzControlView, _ states: [(String, ShotzUI.ControlState)] = ShotzUI.ControlState.gallery) -> [NSView] {
        states.map { _, s in
            let v = make()
            v.stateOverride = s
            v.isSelected = s.isSelected
            v.isEnabled = s.isEnabled
            return v
        }
    }

    static func controlsSheet() -> GallerySheet {
        let sheet = GallerySheet()
        let stateNames = ShotzUI.ControlState.gallery.map(\.0)
        sheet.title("Buttons")
        sheet.header(stateNames)
        sheet.row("Primary", states { ShotzButton(title: "Save", icon: .save, role: .primary) })
        sheet.row("Secondary", states { ShotzButton(title: "Copy", icon: .copy, role: .secondary) })
        sheet.row("Secondary (text)", states { ShotzButton(title: "Choose…", role: .secondary) })
        sheet.row("Quiet (text)", states { ShotzButton(title: "Reset", role: .quiet) })
        sheet.row("Icon button", states { ShotzButton(icon: .more, role: .quiet) })
        sheet.row("Destructive", states { ShotzButton(title: "Delete", icon: .trash, role: .destructive) })
        sheet.row("Sizes", [ShotzButton(title: "Compact", role: .secondary, size: .compact), ShotzButton(title: "Regular", role: .secondary),
                            ShotzButton(title: "Large", role: .secondary, size: .large), ShotzButton(title: "Compact", role: .primary, size: .compact),
                            ShotzButton(title: "Regular", role: .primary), ShotzButton(title: "Large", role: .primary, size: .large)])

        let glass = ImageBackdrop(frame: CGRect(x: 0, y: 0, width: 1132, height: 56))
        sheet.spacer(10)
        sheet.label("Glass (over images): rest · hover · pressed · focused · disabled", style: .label, color: ShotzUI.Palette.textPrimary, at: CGPoint(x: 24, y: sheet.cursor))
        sheet.spacer(22)
        let glassStates: [(String, ShotzUI.ControlState)] = [("rest", .rest), ("hover", .hover), ("pressed", .pressed), ("focused", .focused), ("disabled", .disabled)]
        var gx: CGFloat = 132
        for (_, s) in glassStates {
            for b in [ShotzButton(title: "Copy", role: .glass), ShotzButton(icon: .close, role: .glass)] {
                b.stateOverride = s
                b.isEnabled = s.isEnabled
                let size = b.intrinsicContentSize
                b.frame = CGRect(x: gx, y: (56 - size.height) / 2, width: size.width, height: size.height)
                glass.addSubview(b)
                gx += size.width + 8
            }
            gx += 28
        }
        sheet.block(glass, height: 56)

        sheet.title("Tool button")
        sheet.header(stateNames)
        sheet.row("Tool", states { ShotzToolButton(icon: .arrowTool) })
        let strip = ToolStripExample()
        sheet.row("Tool strip", [strip], height: 44)

        sheet.title("Segmented picker")
        let segStates: [(String, ShotzUI.ControlState)] = [("rest", .rest), ("focused", .focused), ("disabled", .disabled)]
        sheet.header(["rest", "focused", "disabled"], columnWidth: 330)
        let text = segStates.map { _, s -> NSView in
            let c = ShotzSegmentedControl(segments: ["Arrow", "Line", "Shape"].map { .init(title: $0) }, selectedIndex: 1)
            c.stateOverride = s; c.isEnabled = s.isEnabled; return c
        }
        sheet.row("Text", text, columnWidth: 330)
        let arrows = segStates.map { _, s -> NSView in
            let c = ShotzSegmentedControl(segments: [.arrowStraight, .arrowCurved, .arrowTapered, .arrowDoubleHeaded, .arrowLineWithDot].map { .init(icon: $0) }, selectedIndex: 0)
            c.stateOverride = s; c.isEnabled = s.isEnabled; return c
        }
        sheet.row("Icons", arrows, columnWidth: 330)
        let hovered = ShotzSegmentedControl(segments: [.fillOutline, .fillSolid, .fillOutlineTranslucent].map { .init(icon: $0) }, selectedIndex: 0, size: .compact)
        hovered.hoveredIndexOverride = 2
        let first = ShotzSegmentedControl(segments: [.textPlain, .textOutlined, .textSolidPill, .textTranslucentPill].map { .init(icon: $0) }, selectedIndex: 1, size: .compact)
        let last = ShotzSegmentedControl(segments: [.textPlain, .textOutlined, .textSolidPill, .textTranslucentPill].map { .init(icon: $0) }, selectedIndex: 3, size: .compact)
        sheet.row("Compact (hover 3rd)", [hovered], columnWidth: 330)
        sheet.row("Compact (2nd / 4th)", [first, last], columnWidth: 330)
        sheet.title("Colour swatches")
        let swatchStates: [(String, NSView)] = {
            let a = ShotzSwatchRow(swatches: presetSwatches, selectedIndex: 0)
            let b = ShotzSwatchRow(swatches: presetSwatches, selectedIndex: 7); b.hoveredIndexOverride = 2
            let c = ShotzSwatchRow(swatches: presetSwatches, selectedIndex: 8); c.customColor = NSColor(srgbRed: 0.1, green: 0.7, blue: 0.7, alpha: 1)
            let d = ShotzSwatchRow(swatches: presetSwatches, selectedIndex: 6); d.stateOverride = .focused
            let e = ShotzSwatchRow(swatches: presetSwatches, selectedIndex: 0); e.isEnabled = false; e.stateOverride = .disabled
            return [("red", a), ("white · hover", b), ("custom", c), ("focused", d), ("disabled", e)]
        }()
        for (name, v) in swatchStates { sheet.row(name, [v], height: 34) }

        sheet.title("Slider")
        let sliderStates: [(String, Double, ShotzUI.ControlState)] = [("0 %", 0, .rest), ("40 %", 0.4, .rest), ("100 %", 1, .rest),
                                                                       ("pressed", 0.7, .pressed), ("focused", 0.7, .focused), ("disabled", 0.7, .disabled)]
        sheet.header(sliderStates.map(\.0))
        sheet.row("Opacity", sliderStates.map { _, v, s -> NSView in
            let c = ShotzSlider(value: v, icon: .opacity, label: "Opacity", size: .compact)
            c.trackWidth = 72
            c.stateOverride = s; c.isEnabled = s.isEnabled; return c
        })

        sheet.title("Toggle chip")
        let chipStates: [(String, ShotzUI.ControlState)] = [("off", .rest), ("off hover", .hover), ("on", .selected),
                                                            ("on hover", ShotzUI.ControlState(isHovered: true, isSelected: true)), ("focused", .focused), ("disabled", .disabled)]
        sheet.header(chipStates.map(\.0))
        sheet.row("Text", states({ ShotzToggleChip(title: "Outline") }, chipStates))
        sheet.row("Icon + text", states({ ShotzToggleChip(title: "Shadow", icon: .shadow) }, chipStates))
        sheet.finish()
        return sheet
    }

    static func compositionSheet() -> GallerySheet {
        let sheet = GallerySheet(width: 1180)
        sheet.title("Editor toolbar · action area")
        let bar = TitleBarMock(frame: CGRect(x: 0, y: 0, width: 1132, height: 52))
        sheet.block(bar, height: 52)
        sheet.label("Tools left; trailing: zoom │ drag, more │ Copy · Save (secondary) · Done (primary). All 28 pt, 4/8 pt gaps, 12 pt + separator between groups.",
                    at: CGPoint(x: 24, y: bar.frame.maxY + 6))
        sheet.finish()
        return sheet
    }

    @Test func renderGallery() throws {
        guard !GalleryOutput.directories.isEmpty else { return }
        ShotzUI.Palette.accentOverride = GalleryOutput.blue
        defer { ShotzUI.Palette.accentOverride = nil }
        defer { ShotzUI.Palette.increasedContrastOverride = false }
        for (name, appearance) in GalleryOutput.appearances + GalleryOutput.highContrast {
            ShotzUI.Palette.increasedContrastOverride = name.hasSuffix("hc")
            for scale in [CGFloat(1), 2] {
                if name.hasSuffix("hc") && scale == 1 { continue }
                let suffix = "\(name)@\(Int(scale))x.png"
                try GalleryOutput.write(TokensSheet.make().render(appearance: appearance, scale: scale), name: "tokens-\(suffix)")
                try GalleryOutput.write(Self.controlsSheet().render(appearance: appearance, scale: scale), name: "controls-\(suffix)")
                try GalleryOutput.write(Self.compositionSheet().render(appearance: appearance, scale: scale), name: "editor-action-area-\(suffix)")
            }
        }
        ShotzUI.Palette.increasedContrastOverride = false
        // Accent follows the system: the same controls under other accents.
        for (name, appearance) in GalleryOutput.appearances {
            let sheet = GallerySheet(width: 900)
            for (accentName, accent) in [("blue", GalleryOutput.blue), ("purple", NSColor(srgbRed: 0.58, green: 0.33, blue: 0.80, alpha: 1)),
                                         ("orange", NSColor(srgbRed: 0.97, green: 0.51, blue: 0.10, alpha: 1)), ("graphite", NSColor(srgbRed: 0.55, green: 0.55, blue: 0.57, alpha: 1)),
                                         ("green", NSColor(srgbRed: 0.38, green: 0.73, blue: 0.27, alpha: 1)), ("red", NSColor(srgbRed: 1, green: 0.27, blue: 0.23, alpha: 1)),
                                         ("yellow", NSColor(srgbRed: 1.0, green: 0.78, blue: 0.0, alpha: 1))] {
                ShotzUI.Palette.accentOverride = accent
                let tool = ShotzToolButton(icon: .arrowTool); tool.isSelected = true
                let done = ShotzButton(title: "Done", role: .primary)
                let chip = ShotzToggleChip(title: "Outline", isOn: true)
                let slider = ShotzSlider(value: 0.6, icon: .opacity, label: "Opacity", size: .compact); slider.trackWidth = 72
                sheet.row(accentName, [done, tool, chip, slider], height: 40)
                // Render each accent row immediately (dynamic colours resolve at draw time).
                let img = AccentRowSnapshot.capture(sheet, appearance: appearance)
                AccentRowSnapshot.rows.append(img)
            }
            try GalleryOutput.write(AccentRowSnapshot.stack(), name: "accents-\(name)@2x.png")
            AccentRowSnapshot.rows.removeAll()
        }
    }
}
