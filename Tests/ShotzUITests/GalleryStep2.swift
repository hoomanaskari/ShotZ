import AppKit
import ShotzCore
import SwiftUI
import Testing
@testable import ShotzUI

@MainActor
@Suite(.serialized)
struct GalleryStep2Tests {
    init() { _ = NSApplication.shared }

    static func controlsSheet() -> GallerySheet {
        let sheet = GallerySheet()
        sheet.title("Stepped picker · number field · pop-up")
        sheet.header(["rest", "focused", "disabled"], columnWidth: 220)
        let thick: [NSView] = [ShotzUI.ControlState.rest, .focused, .disabled].map { s in
            let c = ShotzSegmentedControl.thicknessPicker(selected: 2); c.stateOverride = s; c.isEnabled = s.isEnabled; return c
        }
        sheet.row("Thickness", thick, columnWidth: 220)
        let numbers: [NSView] = [ShotzUI.ControlState.rest, .focused, .disabled].map { s in
            let n = ShotzNumberField(value: 1920, in: 1...9999, label: "Width", size: .compact); n.suffix = "px"; n.stateOverride = s; n.isEnabled = s.isEnabled; return n
        }
        sheet.row("Number field", numbers, columnWidth: 220)
        sheet.header(["rest", "hover", "pressed", "focused", "disabled"], columnWidth: 160)
        sheet.row("Pop-up (choice)", GalleryTests.states({ ShotzPopUpButton(items: ["Original", "1:1", "4:3", "16:9", "3:2"], selectedIndex: 3) },
                                                         [("", .rest), ("", .hover), ("", .pressed), ("", .focused), ("", .disabled)]), columnWidth: 160)
        sheet.row("Pop-up (quiet)", GalleryTests.states({ let p = ShotzPopUpButton(items: ["100 %"], role: .quiet); p.titleFont = ShotzUI.Typography.value.font; return p },
                                                        [("", .rest), ("", .hover), ("", .pressed), ("", .focused), ("", .disabled)]), columnWidth: 160)
        sheet.row("Pop-up (compact)", [ShotzPopUpButton(items: ["PNG", "JPEG", "HEIC"], size: .compact),
                                       ShotzPopUpButton(items: ["Arrange"], icon: .bringForward, role: .quiet, size: .compact)], columnWidth: 160)

        sheet.title("Toolbar stack · separators")
        let stack = ShotzToolbarStack(groups: [[ShotzButton(icon: .undo, role: .quiet), ShotzButton(icon: .redo, role: .quiet)],
                                               [ShotzButton(icon: .bringForward, role: .quiet), ShotzButton(icon: .sendBackward, role: .quiet)],
                                               [ShotzButton(icon: .trash, role: .quiet)]])
        stack.setFrameSize(stack.intrinsicContentSize)
        sheet.row("Groups", [stack], height: 36)

        sheet.title("Panel · form rows")
        let panel = ShotzPanel(frame: CGRect(x: 0, y: 0, width: 360, height: 196))
        let fill = ShotzSegmentedControl(segments: [.init(title: "None"), .init(title: "Solid"), .init(title: "Gradient")], selectedIndex: 2, size: .compact)
        let padding = ShotzSlider(value: 0.08, in: 0...0.25, icon: .padding, label: "Padding", size: .compact)
        padding.trackWidth = 120
        padding.format = { "\(Int(($0 * 100).rounded())) %" }
        padding.valuePlaceholder = "25 %"
        let shadow = ShotzSegmentedControl(segments: [.init(title: "Off"), .init(title: "Soft"), .init(title: "Strong")], selectedIndex: 1, size: .compact)
        let aspect = ShotzPopUpButton(items: ["Auto", "1:1", "4:3", "16:9", "3:2"], size: .compact)
        let form = ShotzFormStack(rows: [.init("Fill", fill), .init("Padding", padding), .init("Shadow", shadow), .init("Aspect", aspect)], labelWidth: 64)
        form.frame = CGRect(x: 0, y: 0, width: 328, height: form.intrinsicContentSize.height)
        panel.contentView.addSubview(form)
        panel.layoutSubtreeIfNeeded()
        sheet.block(panel, height: 196, x: 24 + sheet.labelWidth)

        sheet.title("Toast · key caps")
        sheet.row("Toast", [ShotzToast("Copied"), ShotzToast("Saved to Desktop"), ShotzToast("Couldn't save", tone: .failure)], height: 40, columnWidth: 200)
        sheet.row("Key caps", [ShotzKeyCaps(["⌘", "⇧", "4"]), ShotzKeyCaps(["⌃", "⌥", "⌘", "3"]), ShotzKeyCaps(["Space"])], height: 30, columnWidth: 200)
        sheet.finish()
        return sheet
    }

    static func compositionsSheet() -> GallerySheet {
        let sheet = GallerySheet(width: 1180)
        sheet.title("Options bar (arrow tool)")
        let bar = EditorOptionsBar(swatches: GalleryTests.presetSwatches)
        bar.frame = CGRect(x: 0, y: 0, width: 1132, height: EditorOptionsBar.height)
        bar.layoutSubtreeIfNeeded()
        sheet.block(bar, height: EditorOptionsBar.height)
        sheet.title("Quick-access card on hover (250 × 156)")
        let backdrop = ImageBackdrop(frame: .zero)
        let card = StackCardHover(frame: CGRect(x: 0, y: 0, width: 250, height: 156))
        card.drawImage = { _, rect in backdrop.frame = rect; backdrop.draw(rect) }
        card.layoutSubtreeIfNeeded()
        let card2 = StackCardHover(frame: CGRect(x: 0, y: 0, width: 250, height: 156))
        card2.drawImage = card.drawImage
        card2.copyButton.stateOverride = .hover
        card2.layoutSubtreeIfNeeded()
        let holder = NSView(frame: CGRect(x: 0, y: 0, width: 560, height: 156))
        holder.addSubview(card)
        card2.frame.origin.x = 290
        holder.addSubview(card2)
        sheet.block(holder, height: 156, x: 24 + sheet.labelWidth)
        sheet.label("Left: rest of the hover state. Right: pointer over Copy.", at: CGPoint(x: 24 + sheet.labelWidth, y: sheet.cursor - 6))
        sheet.finish()
        return sheet
    }

    @Test func renderStep2Gallery() throws {
        guard !GalleryOutput.directories.isEmpty else { return }
        ShotzUI.Palette.accentOverride = GalleryOutput.blue
        defer { ShotzUI.Palette.accentOverride = nil; ShotzUI.Palette.increasedContrastOverride = false }
        for (name, appearance) in GalleryOutput.appearances + GalleryOutput.highContrast {
            ShotzUI.Palette.increasedContrastOverride = name.hasSuffix("hc")
            for scale in [CGFloat(1), 2] {
                if name.hasSuffix("hc") && scale == 1 { continue }
                let suffix = "\(name)@\(Int(scale))x.png"
                try GalleryOutput.write(Self.controlsSheet().render(appearance: appearance, scale: scale), name: "controls-2-\(suffix)")
                try GalleryOutput.write(Self.compositionsSheet().render(appearance: appearance, scale: scale), name: "compositions-\(suffix)")
                // SwiftUI Settings pane.
                let renderer = ImageRenderer(content: SettingsPaneExample().environment(\.colorScheme, name.hasPrefix("dark") ? .dark : .light))
                renderer.scale = scale
                var image: CGImage?
                appearance.performAsCurrentDrawingAppearance { image = renderer.cgImage }
                if let image { try GalleryOutput.write(image, name: "settings-pane-\(suffix)") }
            }
        }
    }
}
