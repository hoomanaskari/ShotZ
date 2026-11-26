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

        sheet.title("Editor panel controls")
        sheet.header(["rest", "hover", "on", "focused", "disabled"], columnWidth: 160)
        let cbStates: [(String, ShotzUI.ControlState)] = [("", .rest), ("", .hover), ("", .selected), ("", .focused), ("", .disabled)]
        sheet.row("Checkbox", GalleryTests.states({ ShotzCheckbox("Snap") }, cbStates), columnWidth: 160)
        sheet.row("Switch", GalleryTests.states({ ShotzSwitch(label: "Background") }, cbStates), columnWidth: 160)
        sheet.row("Colour well", GalleryTests.states({ ShotzColorWell(color: NSColor(srgbRed: 0.1, green: 0.6, blue: 0.7, alpha: 1), label: "Custom") }, cbStates), columnWidth: 160)
        sheet.row("Tile", GalleryTests.states({ ShotzTileButton(image: Self.gradientTile(), label: "Lagoon") }, cbStates), columnWidth: 160)
        sheet.row("Icon chip", GalleryTests.states({ ShotzToggleChip(icon: .shadow, label: "Shadow") }, cbStates), columnWidth: 160)
        let labels = NSView(frame: CGRect(x: 0, y: 0, width: 700, height: 22))
        var lx: CGFloat = 0
        for (t, role) in [("Background", ShotzUI.LabelRole.panelTitle), ("Padding", .formLabel), ("Applies to the export only.", .note), ("1920 × 1080", .caption)] {
            let l = ShotzUI.label(t, role); l.sizeToFit(); l.frame.origin = CGPoint(x: lx, y: 2); labels.addSubview(l); lx += l.frame.width + 40
        }
        sheet.row("Labels", [labels], height: 26)

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
        sheet.title("Quick-access cards on hover: small · medium · large")
        let backdrop = ImageBackdrop(frame: .zero)
        let holder = NSView(frame: CGRect(x: 0, y: 0, width: 760, height: 156))
        var x: CGFloat = 0
        for size in ShotzUI.CardSize.allCases {
            let card = StackCardHover(cardSize: size)
            card.drawImage = { _, rect in backdrop.frame = rect; backdrop.draw(rect) }
            if size == .large { card.copyButton.stateOverride = .hover }
            card.frame.origin = CGPoint(x: x, y: 156 - size.height)
            card.layoutSubtreeIfNeeded()
            holder.addSubview(card)
            x += size.width + 40
        }
        sheet.block(holder, height: 156, x: 24 + sheet.labelWidth)
        sheet.label("Large card shows the pointer over Copy. Small cards use icon-only centre buttons.", at: CGPoint(x: 24 + sheet.labelWidth, y: sheet.cursor - 6))
        sheet.spacer(16)
        sheet.title("Glass pieces")
        let strip = ImageBackdrop(frame: CGRect(x: 0, y: 0, width: 1132, height: 52))
        var gx: CGFloat = 16
        func put(_ v: NSView) {
            let s = v.intrinsicContentSize
            v.frame = CGRect(x: gx, y: ((52 - s.height) / 2).rounded(), width: s.width, height: s.height)
            strip.addSubview(v)
            gx += s.width + 14
        }
        for size in ShotzUI.CardSize.allCases { put(ShotzGlassIconButton(icon: .annotate, cardSize: size)) }
        let pressed = ShotzGlassIconButton(icon: .close); pressed.stateOverride = .pressed; put(pressed)
        put(ShotzButton.glass("Copy", icon: .copy, cardSize: .large)); put(ShotzButton.glass("Save", icon: .save, cardSize: .medium))
        put(ShotzButton.glass("Save", icon: .save, cardSize: .small))
        for size in ShotzUI.CardSize.allCases { put(ShotzCaptionPill("1920 × 1080", cardSize: size)) }
        put(ShotzToast("Copied", compact: true)); put(ShotzToast("Couldn't save", tone: .failure, compact: true))
        sheet.block(strip, height: 52)
        sheet.label("Glass circles 22 / 24 / 26 pt, pressed; Copy · Save pairs (large, medium, small); caption pills; compact toasts.",
                    at: CGPoint(x: 24, y: sheet.cursor - 6))
        sheet.spacer(12)
        sheet.finish()
        return sheet
    }

    static func gradientTile() -> NSImage {
        NSImage(size: NSSize(width: 36, height: 24), flipped: false) { r in
            NSGradient(starting: NSColor(srgbRed: 0.36, green: 0.86, blue: 0.80, alpha: 1), ending: NSColor(srgbRed: 0.18, green: 0.42, blue: 0.82, alpha: 1))?.draw(in: r, angle: -45)
            return true
        }
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
                let form = ImageRenderer(content: SettingsFormSample().environment(\.colorScheme, name.hasPrefix("dark") ? .dark : .light))
                form.scale = scale
                var formImage: CGImage?
                appearance.performAsCurrentDrawingAppearance { formImage = form.cgImage }
                if let formImage { try GalleryOutput.write(formImage, name: "settings-form-\(suffix)") }
            }
        }
    }
}

/// A's label-column layout with help text, status badge and the shortcut field in its states.
struct SettingsFormSample: View {
    var body: some View {
        ShotzSettingsPane {
            ShotzSettingsSection("Shortcuts") {
                VStack(alignment: .leading, spacing: 0) {
                    ShotzFormRow("Capture area") {
                        ShotzShortcutField(keys: ["⌘", "⇧", "4"], isRecording: false, title: "Capture area", onToggle: {}, onClear: {})
                    }
                    ShotzFormRow("Capture fullscreen") {
                        ShotzShortcutField(keys: [], isRecording: true, heldModifiers: ["⌃", "⌥"], title: "Capture fullscreen", onToggle: {}, onClear: {})
                    }
                    ShotzFormRow("All-in-one") {
                        ShotzShortcutField(keys: ["⌘", "⇧", "5"], isRecording: false, hasWarning: true, title: "All-in-one", onToggle: {}, onClear: {})
                        ShotzHelpText("Another app already uses this shortcut.", tone: .warning)
                    }
                    ShotzFormRow("Restore last closed") {
                        ShotzShortcutField(keys: [], isRecording: false, title: "Restore last closed", onToggle: {}, onClear: {})
                        ShotzHelpText("No default shortcut.")
                    }
                }
                .padding(.horizontal, ShotzUI.Space.l)
                .padding(.vertical, ShotzUI.Space.s)
            }
            ShotzSettingsSection("Permission") {
                ShotzSettingsRow("Screen Recording", help: "Needed to capture the screen.") {
                    HStack(spacing: ShotzUI.Space.s) {
                        ShotzStatusBadge("Not allowed", positive: false)
                        Button("Open Settings") {}.buttonStyle(.shotz(.secondary, size: .compact))
                    }
                }
                ShotzSettingsRow("Accessibility") { ShotzStatusBadge("Allowed", positive: true) }
            }
            ShotzBanner("Couldn't register ⌘⇧5: another app holds it.", tone: .warning, actionTitle: "Use alternate", action: {})
            HStack {
                Toggle("Snap while moving", isOn: .constant(true)).toggleStyle(.shotzCheckbox)
                Toggle("Close after copy", isOn: .constant(false)).toggleStyle(.shotzCheckbox)
            }
        }
    }
}
