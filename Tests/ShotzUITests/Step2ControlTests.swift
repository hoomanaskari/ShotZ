import AppKit
import ShotzCore
import Testing
@testable import ShotzUI

@MainActor
struct Step2ControlTests {
    init() { _ = NSApplication.shared }

    @Test func popUpSelectionAndAccessibility() {
        let p = ShotzPopUpButton(items: ["PNG", "JPEG", "HEIC"], selectedIndex: 1)
        #expect(p.title == "JPEG" && p.accessibilityRole() == .popUpButton && (p.accessibilityValue() as? String) == "JPEG")
        let w = p.intrinsicContentSize.width
        p.selectedIndex = 0
        #expect(p.intrinsicContentSize.width == w, "width reserves the widest item")
        #expect(p.intrinsicContentSize.height >= 28)
    }

    @Test func numberFieldClampsAndFormats() {
        let n = ShotzNumberField(value: 50, in: 1...100, step: 10, label: "Width")
        n.suffix = "px"
        n.value = 250
        #expect(n.value == 100 && (n.accessibilityValue() as? String) == "100 px")
        n.value = -5
        #expect(n.value == 1)
        #expect(n.intrinsicContentSize.height >= 28)
    }

    @Test func toolbarStackRhythm() {
        let a = ShotzButton(icon: .undo, role: .quiet), b = ShotzButton(icon: .redo, role: .quiet), c = ShotzButton(icon: .trash, role: .quiet)
        let stack = ShotzToolbarStack(groups: [[a, b], [c]])
        stack.frame = CGRect(origin: .zero, size: stack.intrinsicContentSize)
        stack.layoutSubtreeIfNeeded()
        #expect(b.frame.minX - a.frame.maxX == ShotzUI.Space.xs)
        #expect(c.frame.minX - b.frame.maxX == 2 * ShotzUI.Space.m + 1)
        #expect(stack.intrinsicContentSize.width == c.frame.maxX)
    }

    @Test func formStackAlignsControls() {
        let x = ShotzPopUpButton(items: ["Auto"], size: .compact), y = ShotzSegmentedControl.thicknessPicker(selected: 0)
        let form = ShotzFormStack(rows: [.init("Aspect", x), .init("Thickness", y)], labelWidth: 70)
        form.frame = CGRect(origin: .zero, size: form.intrinsicContentSize)
        form.layoutSubtreeIfNeeded()
        #expect(x.frame.minX == y.frame.minX && x.frame.minX == 70 + ShotzUI.Space.m)
        #expect(y.frame.minY >= x.frame.maxY)
    }

    @Test func toastAndKeyCapsAreReadable() {
        let t = ShotzToast("Copied")
        #expect(t.accessibilityLabel() == "Copied" && t.intrinsicContentSize.height == 32)
        let k = ShotzKeyCaps(["⌘", "⇧", "4"])
        #expect(k.accessibilityLabel() == "⌘⇧4" && k.intrinsicContentSize.width > 3 * 20)
    }

    @Test func compositionsUseOnePrimary() {
        let area = EditorActionArea()
        let buttons = area.subviews.compactMap { $0 as? ShotzButton }
        #expect(buttons.filter { $0.role == .primary } == [area.doneButton])
        #expect(area.copyButton.intrinsicContentSize.width == area.saveButton.intrinsicContentSize.width)
        #expect(buttons.allSatisfy { $0.toolTip != nil }, "every action needs a tooltip")
        for size in ShotzUI.CardSize.allCases {
            let card = StackCardHover(cardSize: size)
            card.layoutSubtreeIfNeeded()
            #expect(card.frame.size == CGSize(width: size.width, height: size.height))
            #expect(card.subviews.compactMap { $0 as? ShotzButton }.allSatisfy { $0.role == .glass && $0.toolTip != nil })
            #expect(card.subviews.compactMap { $0 as? ShotzGlassIconButton }.allSatisfy { $0.toolTip != nil && $0.intrinsicContentSize.width >= 28 })
            #expect(card.copyButton.intrinsicContentSize.width == card.saveButton.intrinsicContentSize.width)
            // Corner circles sit exactly `cornerInset` from the edges.
            let circleMinX = card.closeButton.frame.midX - size.glassDiameter / 2
            #expect(abs(circleMinX - size.cornerInset) < 0.01)
        }
    }
}

@MainActor
struct EditorPanelControlTests {
    init() { _ = NSApplication.shared }

    @Test func checkboxSwitchAndChip() {
        let c = ShotzCheckbox("Snap")
        #expect(c.accessibilityRole() == .checkBox && (c.accessibilityValue() as? Int) == 0)
        c.isOn = true
        #expect((c.accessibilityValue() as? Int) == 1)
        let s = ShotzSwitch(isOn: true, label: "Background")
        #expect(s.knob == 1 && s.accessibilityLabel() == "Background" && s.intrinsicContentSize.height >= 28)
        let chip = ShotzToggleChip(icon: .shadow, label: "Shadow")
        #expect(chip.accessibilityLabel() == "Shadow" && chip.toolTip == "Shadow" && chip.intrinsicContentSize.width < 40)
    }

    @Test func segmentedThumbIsPixelExact() {
        for count in 2...6 {
            let c = ShotzSegmentedControl(segments: Array(repeating: .init(icon: .textPlain), count: count), selectedIndex: 0, size: .compact)
            c.frame = CGRect(origin: .zero, size: c.intrinsicContentSize)
            // Intrinsic width gives every segment the same whole-point width.
            #expect((c.intrinsicContentSize.width - 4).truncatingRemainder(dividingBy: CGFloat(count)) == 0)
        }
    }
}
