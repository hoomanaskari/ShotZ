import AppKit
import ShotzCore
import Testing
@testable import ShotzUI
import ShotzTestSupport

/// Every ShotzUI control type driven by real in-process mouse events (PointerDriver): what a click
/// or a drag at a given place does. Each control sits far from the window origin, so a coordinate
/// conversion mistake would show. (The pop-up button's menu and the colour well's panel run AppKit's
/// own modal tracking and are covered by their selection tests instead.)
@MainActor
struct PointerInteractionTests {
    /// Hosts `control` at (400, 200) in an off-screen 900 × 400 window.
    static func host(_ control: NSView, width: CGFloat? = nil) -> NSWindow {
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 900, height: 400))
        let size = control.intrinsicContentSize
        control.frame = CGRect(x: 400, y: 200, width: width ?? max(size.width, 40), height: max(size.height, 24))
        content.addSubview(control)
        return PointerDriver.window(hosting: content, size: content.frame.size)
    }

    /// The x of `fraction` along a slider's track (the track starts after the knob's half width).
    static func trackPoint(_ s: ShotzSlider, _ fraction: CGFloat) -> CGPoint {
        let knob: CGFloat = 16
        let right = ShotzUI.Space.s + ceil(("100 %" as NSString).size(withAttributes: [.font: ShotzUI.Typography.value.font]).width) + knob / 2
        let left = knob / 2
        return CGPoint(x: left + (s.bounds.width - left - right) * fraction, y: s.bounds.midY)
    }

    // MARK: Slider

    @Test func sliderClicksLandWhereClicked() async {
        for fraction in [0.25, 0.5, 0.75] as [CGFloat] {
            let s = ShotzSlider(value: 0, in: 0...100, label: "Test")
            let w = Self.host(s, width: 240)
            var commits: [Double] = []
            s.onCommit = { commits.append($0) }
            await PointerDriver.click(s, at: Self.trackPoint(s, fraction))
            #expect(abs(s.value - Double(fraction) * 100) < 1, "click at \(fraction): \(s.value)")
            #expect(commits.count == 1, "one commit per click")
            _ = w
        }
    }

    @Test func sliderDragFollowsThePointerBothWays() async {
        let s = ShotzSlider(value: 0, in: 0...100, label: "Test")
        let w = Self.host(s, width: 240)
        var changes: [Double] = [], commits: [Double] = []
        s.onChange = { changes.append($0) }
        s.onCommit = { commits.append($0) }
        var seen: [Double] = []
        let path: [CGFloat] = [0.4, 0.6, 0.8, 0.5, 0.2]
        await PointerDriver.press(s, at: Self.trackPoint(s, 0.2), dragging: path.map { Self.trackPoint(s, $0) }) { _ in seen.append(s.value) }
        let expected = ([0.2] + path).map { Double($0) * 100 }
        #expect(seen.count == expected.count)
        for (v, e) in zip(seen, expected) { #expect(abs(v - e) < 1, "seen \(seen)") }
        // seen[0] is after the press; the drag goes right (1…3), then back left (4, 5).
        #expect(seen[4] < seen[3] && seen[5] < seen[4], "dragging back left decreases the value")
        #expect(abs(s.value - 20) < 1)
        #expect(commits.count == 1 && abs(commits[0] - 20) < 1, "one commit, at mouse-up")
        #expect(changes.count >= 5)
        _ = w
    }

    @Test func sliderClampsAtBothEnds() async {
        let s = ShotzSlider(value: 50, in: 0...100, label: "Test")
        let w = Self.host(s, width: 240)
        await PointerDriver.press(s, at: Self.trackPoint(s, 0.5), dragging: [CGPoint(x: -300, y: s.bounds.midY)])
        #expect(s.value == 0)
        await PointerDriver.press(s, at: Self.trackPoint(s, 0.5), dragging: [CGPoint(x: s.bounds.width + 300, y: s.bounds.midY)])
        #expect(s.value == 100)
        await PointerDriver.click(s, at: CGPoint(x: 1, y: s.bounds.midY))
        #expect(s.value == 0)
        _ = w
    }

    /// The 0.1.0/0.1.1 bug's mechanism: the app replaces the slider while the drag is still going
    /// (work queued on the main queue runs inside AppKit's tracking). The detached slider must stop
    /// tracking instead of reading window points as its own and jumping to the far end.
    @Test func aSliderReplacedMidDragNeitherJumpsNorKeepsTracking() async {
        let s = ShotzSlider(value: 0, in: 0...100, label: "Test")
        let w = Self.host(s, width: 240)
        var commits: [Double] = []
        s.onCommit = { commits.append($0) }
        s.onChange = { _ in DispatchQueue.main.async { s.removeFromSuperview() } }   // a rebuild, mid-drag
        await PointerDriver.press(s, at: Self.trackPoint(s, 0.3), dragging: [Self.trackPoint(s, 0.4), Self.trackPoint(s, 0.5)])
        #expect(s.value < 50, "no jump: \(s.value)")
        #expect(abs(s.value - 30) < 1, "the value from before the replacement stays: \(s.value)")
        #expect(commits.count == 1, "the press still ends with one commit")
        _ = w
    }

    @Test func sliderKeysStepAndCommit() {
        let s = ShotzSlider(value: 50, in: 0...100, step: 5, label: "Test")
        var commits: [Double] = []
        s.onCommit = { commits.append($0) }
        _ = s.accessibilityPerformIncrement()
        _ = s.accessibilityPerformDecrement()
        _ = s.accessibilityPerformDecrement()
        #expect(s.value == 45)
        #expect(commits == [55, 50, 45])
    }

    // MARK: Buttons and toggles

    @Test func buttonsActOnAClickButNotWhenReleasedOutside() async {
        let controls: [ShotzControlView] = [ShotzButton(title: "Go"), ShotzToolButton(icon: .arrowTool),
                                           ShotzGlassIconButton(icon: .close),
                                           ShotzTileButton(image: NSImage(size: CGSize(width: 18, height: 12)), label: "Tile")]
        for c in controls {
            let w = Self.host(c)
            var actions = 0
            c.onAction = { _ in actions += 1 }
            await PointerDriver.click(c, at: CGPoint(x: c.bounds.midX, y: c.bounds.midY))
            #expect(actions == 1, "\(type(of: c)): a click acts")
            await PointerDriver.press(c, at: CGPoint(x: c.bounds.midX, y: c.bounds.midY), dragging: [CGPoint(x: c.bounds.maxX + 50, y: c.bounds.midY)])
            #expect(actions == 1, "\(type(of: c)): released outside, no action")
            _ = w
        }
    }

    @Test func togglesFlipOnEachClick() async {
        let check = ShotzCheckbox("Auto-balance"), sw = ShotzSwitch(label: "On"), chip = ShotzToggleChip(title: "Bold")
        var flips: [String] = []
        check.onToggle = { flips.append("check \($0)") }
        sw.onToggle = { flips.append("switch \($0)") }
        chip.onToggle = { flips.append("chip \($0)") }
        for c in [check, sw, chip] as [ShotzControlView] {
            let w = Self.host(c)
            await PointerDriver.click(c, at: CGPoint(x: c.bounds.midX, y: c.bounds.midY))
            await PointerDriver.click(c, at: CGPoint(x: c.bounds.midX, y: c.bounds.midY))
            _ = w
        }
        #expect(flips == ["check true", "check false", "switch true", "switch false", "chip true", "chip false"])
    }

    // MARK: Choices

    @Test func segmentedControlSelectsTheClickedSegment() async {
        let seg = ShotzSegmentedControl(segments: ["Off", "Soft", "Strong", "Max"].map { .init(title: $0) }, selectedIndex: 0)
        let w = Self.host(seg, width: 280)
        var chosen: [Int] = []
        seg.onChange = { chosen.append($0) }
        for i in [2, 1, 3, 0] {
            await PointerDriver.click(seg, at: CGPoint(x: seg.bounds.width * (CGFloat(i) + 0.5) / 4, y: seg.bounds.midY))
            #expect(seg.selectedIndex == i)
        }
        #expect(chosen == [2, 1, 3, 0])
        _ = w
    }

    @Test func swatchRowSelectsTheClickedSwatch() async {
        let colours: [NSColor] = [.red, .orange, .yellow, .green, .blue]
        let row = ShotzSwatchRow(swatches: colours.enumerated().map { .init($1, name: "c\($0)") }, selectedIndex: 0)
        let w = Self.host(row)
        var chosen: [Int] = []
        row.onSelect = { chosen.append($0) }
        for i in [3, 1, 4] {
            // Cells are 28 pt wide (the row ends with an extra custom-colour cell).
            await PointerDriver.click(row, at: CGPoint(x: 28 * (CGFloat(i) + 0.5), y: row.bounds.midY))
            #expect(row.selectedIndex == i, "swatch \(i)")
        }
        #expect(chosen == [3, 1, 4])
        _ = w
    }

    @Test func numberFieldSteppersChangeTheValue() async {
        let field = ShotzNumberField(value: 10, in: 0...20, step: 1, label: "Width")
        let w = Self.host(field, width: 140)
        field.layoutSubtreeIfNeeded()
        let buttons = PointerDriver.all(ShotzControlView.self, in: field)
        #expect(buttons.count >= 2, "− and + steppers")
        var values: [Double] = []
        field.onChange = { values.append($0) }
        if let minus = buttons.first, let plus = buttons.last {
            await PointerDriver.click(plus, at: CGPoint(x: plus.bounds.midX, y: plus.bounds.midY))
            await PointerDriver.click(plus, at: CGPoint(x: plus.bounds.midX, y: plus.bounds.midY))
            await PointerDriver.click(minus, at: CGPoint(x: minus.bounds.midX, y: minus.bounds.midY))
        }
        #expect(field.value == 11, "values: \(values)")
        _ = w
    }
}
