import AppKit
import Testing
@testable import ShotzUI

@MainActor
struct StateModelTests {
    let light = NSAppearance(named: .aqua)!

    func bg(_ role: ShotzUI.ControlRole, _ s: ShotzUI.ControlState) -> NSColor? { ShotzUI.fills(for: role, state: s).background?.resolved(in: light) }
    func same(_ a: NSColor?, _ b: NSColor?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.redComponent - b.redComponent) + abs(a.greenComponent - b.greenComponent) + abs(a.blueComponent - b.blueComponent) + abs(a.alphaComponent - b.alphaComponent) < 0.002
    }

    @Test(arguments: ShotzUI.ControlRole.allCases) func hoverAndPressAreVisible(_ role: ShotzUI.ControlRole) {
        // Chips and tools must also respond when off/unselected.
        #expect(!same(bg(role, .rest), bg(role, .hover)), "\(role): hover looks like rest")
        #expect(!same(bg(role, .hover), bg(role, .pressed)), "\(role): pressed looks like hover")
    }

    @Test func selectionTintsToolsAndChips() {
        for role in [ShotzUI.ControlRole.tool, .chip] {
            let s = ShotzUI.fills(for: role, state: .selected)
            #expect(s.background != nil && s.border != nil)
            #expect(same(s.content.resolved(in: light), ShotzUI.Palette.selectedContent.resolved(in: light)))
        }
        #expect(ShotzUI.fills(for: .tool, state: .rest).background == nil)
        #expect(ShotzUI.fills(for: .quiet, state: .rest).background == nil)
    }

    @Test(arguments: ShotzUI.ControlRole.allCases) func disabledIsMuted(_ role: ShotzUI.ControlRole) {
        let d = ShotzUI.fills(for: role, state: .disabled)
        #expect(!d.raised)
        if role != .primary {
            #expect(same(d.content.resolved(in: light), ShotzUI.Palette.textTertiary.resolved(in: light)) || role == .glass)
        }
    }

    @Test func controlSizesMeetHitTargets() {
        for s in ShotzUI.ControlSize.allCases {
            #expect(s.hitHeight >= 28)
            #expect(s.iconSize < s.height && s.radius < s.height / 2)
        }
        #expect(ShotzUI.ToolMetrics.size >= 28)
        for v in [ShotzUI.Space.xs, ShotzUI.Space.s, ShotzUI.Space.m, ShotzUI.Space.l, ShotzUI.Space.xl, ShotzUI.Space.xxl] { #expect(v.truncatingRemainder(dividingBy: 4) == 0) }
    }

    @Test func controlsReportAccessibilityAndStableSizes() {
        let save = ShotzButton(title: "Save", icon: .save, role: .primary)
        #expect(save.accessibilityLabel() == "Save" && save.accessibilityRole() == .button)
        #expect(save.intrinsicContentSize.height >= 28)
        let more = ShotzButton(icon: .more, role: .quiet)
        #expect(more.accessibilityLabel() == "More" && more.intrinsicContentSize == NSSize(width: 28, height: 28))
        let chip = ShotzToggleChip(title: "Outline")
        let off = chip.intrinsicContentSize
        chip.isOn = true
        #expect(chip.intrinsicContentSize == off, "toggling must not change the chip's width")
        #expect(chip.accessibilityRole() == .checkBox && (chip.accessibilityValue() as? Int) == 1)
        let seg = ShotzSegmentedControl(segments: [.init(title: "A"), .init(title: "B")], selectedIndex: 1)
        #expect(seg.accessibilityChildren()?.count == 2 && (seg.accessibilityValue() as? String) == "B")
        seg.select(0, animated: false)
        #expect((seg.accessibilityValue() as? String) == "A" && seg.thumbPosition == 0)
        let slider = ShotzSlider(value: 0.5, label: "Opacity")
        #expect(slider.accessibilityRole() == .slider && (slider.accessibilityValue() as? String) == "50 %")
        slider.value = 2
        #expect(slider.value == 1)
        let tool = ShotzToolButton(icon: .arrowTool)
        tool.isSelected = true
        #expect(tool.accessibilityLabel() == "Arrow" && (tool.accessibilityValue() as? Int) == 1)
    }
}
