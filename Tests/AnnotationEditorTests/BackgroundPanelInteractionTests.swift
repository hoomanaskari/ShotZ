import AnnotationKit
import AppKit
import Testing
@testable import AnnotationEditor
import ShotzTestSupport
@testable import ShotzUI

/// The Background panel driven through its real controls with real in-process mouse events.
@MainActor
struct BackgroundPanelInteractionTests {
    @MainActor struct Fixture {
        let model: EditorModel
        let panel: BackgroundPanelView
        let window: NSWindow
        func slider(_ label: String) -> ShotzSlider? { control(ShotzSlider.self, label) }
        /// A control found by its accessibility label (re-found after each change: the panel rebuilds).
        func control<T: NSView>(_ type: T.Type, _ label: String) -> T? {
            PointerDriver.all(T.self, in: panel).first { $0.accessibilityLabel() == label }
        }
        var style: AnnotationKit.BackgroundStyle? { model.document.background }
        func centre(_ v: NSView) -> CGPoint { CGPoint(x: v.bounds.midX, y: v.bounds.midY) }
        /// Clicks segment `i` of an n-segment control.
        func clickSegment(_ seg: ShotzSegmentedControl, _ i: Int, of n: Int) async {
            await PointerDriver.click(seg, at: CGPoint(x: seg.bounds.width * (CGFloat(i) + 0.5) / CGFloat(n), y: seg.bounds.midY))
        }
    }

    static func fixture(_ style: AnnotationKit.BackgroundStyle = .init()) -> Fixture {
        let model = makeModel()
        model.setBackground(style, interactive: false)
        let presets = BackgroundPresets(defaults: MemoryDefaults())
        let panel = BackgroundPanelView(model: model, presets: presets)
        // As in the editor: the panel is a sidebar at the right of a wide window, so window and
        // panel coordinates differ by about a thousand points.
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 1400, height: 900))
        panel.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.trailingAnchor.constraint(equalTo: content.trailingAnchor),
            panel.topAnchor.constraint(equalTo: content.topAnchor),
            panel.bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
        let window = PointerDriver.window(hosting: content, size: content.frame.size)
        return Fixture(model: model, panel: panel, window: window)
    }

    @Test func paddingSliderFollowsADragBackAndForth() async throws {
        let f = Self.fixture(.init(padding: 0.10))
        let slider = try #require(f.slider("Padding"))
        let track = { (fraction: CGFloat) -> CGPoint in CGPoint(x: slider.trackRect.minX + slider.trackRect.width * fraction, y: slider.bounds.midY) }
        var seen: [Double] = []
        await PointerDriver.press(slider, at: track(0.5), dragging: [track(0.6), track(0.7), track(0.4), track(0.3)]) { _ in
            seen.append((f.model.document.background?.padding ?? -1) * 100)
        }
        // Values only increase then decrease with the pointer; none jumps to the 25 % maximum.
        #expect(seen.allSatisfy { $0 < 24 }, "values during the drag: \(seen)")
        let final = try #require(f.model.document.background?.padding) * 100
        #expect(abs(final - 7.5) < 0.5, "released at 30 % of the track: \(final) %")
    }

    // MARK: Position grid

    @Test func everyPositionCellMovesTheImage() async throws {
        let f = Self.fixture(.init(padding: 0.10))
        let centre = BackgroundLayout(document: f.model.document).imageFrame
        for a in AnnotationKit.BackgroundStyle.Alignment.allCases {
            let tile = try #require(f.control(ShotzTileButton.self, BackgroundPanelView.alignmentName(a)), "\(a) tile")
            #expect(tile.isEnabled)
            await PointerDriver.click(tile, at: f.centre(tile))
            #expect(f.style?.alignment == a, "clicking \(a)")
            let frame = BackgroundLayout(document: f.model.document).imageFrame
            #expect((frame.origin == centre.origin) == (a == .center), "\(a) moves the image: \(frame.origin) vs centre \(centre.origin)")
        }
    }

    @Test func positionIsDisabledWithExplanationWhenThereIsNoRoom() async throws {
        let f = Self.fixture(.init(padding: 0))
        let tile = try #require(f.control(ShotzTileButton.self, BackgroundPanelView.alignmentName(.topLeft)))
        #expect(!tile.isEnabled)
        await PointerDriver.click(tile, at: f.centre(tile))
        #expect(f.style?.alignment == .center, "a disabled cell does nothing")
        let notes = PointerDriver.all(NSTextField.self, in: f.panel).map(\.stringValue)
        #expect(notes.contains { $0.contains("Add padding or choose an aspect") }, "explains why: \(notes)")
        // Choosing a fixed aspect enables the grid.
        let aspect = try #require(f.control(ShotzSegmentedControl.self, "Aspect"))
        await f.clickSegment(aspect, 1, of: AnnotationKit.BackgroundStyle.Aspect.allCases.count)
        #expect(f.style?.aspect == .square)
        #expect(f.control(ShotzTileButton.self, BackgroundPanelView.alignmentName(.topLeft))?.isEnabled == true)
    }

    // MARK: Every other control

    @Test func aspectShadowAndFillFollowClicks() async throws {
        let f = Self.fixture(.init(padding: 0.10))
        let aspects = AnnotationKit.BackgroundStyle.Aspect.allCases
        for (i, a) in aspects.enumerated().reversed() {
            await f.clickSegment(try #require(f.control(ShotzSegmentedControl.self, "Aspect")), i, of: aspects.count)
            #expect(f.style?.aspect == a, "aspect \(a)")
        }
        let shadows = AnnotationKit.BackgroundStyle.Shadow.allCases
        for (i, sh) in shadows.enumerated().reversed() {
            await f.clickSegment(try #require(f.control(ShotzSegmentedControl.self, "Shadow")), i, of: shadows.count)
            #expect(f.style?.shadow == sh, "shadow \(sh)")
        }
        await f.clickSegment(try #require(f.control(ShotzSegmentedControl.self, "Fill")), 0, of: 3)
        if case .some(.none) = f.style?.fill {} else { Issue.record("fill none: \(String(describing: f.style?.fill))") }
        await f.clickSegment(try #require(f.control(ShotzSegmentedControl.self, "Fill")), 1, of: 3)
        if case .solid = f.style?.fill {} else { Issue.record("fill colour") }
        await f.clickSegment(try #require(f.control(ShotzSegmentedControl.self, "Fill")), 2, of: 3)
        guard case .gradient = f.style?.fill else { Issue.record("fill gradient"); return }
        // A gradient preset tile applies that gradient.
        let preset = GradientPreset.all[5]
        let tile = try #require(f.control(ShotzTileButton.self, preset.name))
        await PointerDriver.click(tile, at: f.centre(tile))
        if case .gradient(let g) = f.style?.fill { #expect(g == preset.fill) } else { Issue.record("preset tile") }
    }

    @Test func autoBalanceToggles() async throws {
        let f = Self.fixture(.init(padding: 0.10, autoBalance: false))
        let box = try #require(f.control(ShotzCheckbox.self, "Auto-balance"))
        await PointerDriver.click(box, at: f.centre(box))
        #expect(f.style?.autoBalance == true)
        let again = try #require(f.control(ShotzCheckbox.self, "Auto-balance"))
        await PointerDriver.click(again, at: f.centre(again))
        #expect(f.style?.autoBalance == false)
    }

    @Test func cornersAndAngleSlidersFollowDrags() async throws {
        let f = Self.fixture(.init(fill: .gradient(BackgroundPresets.gradients[1]), padding: 0.10))
        for (label, read, max) in [("Corner radius", { (s: AnnotationKit.BackgroundStyle) in Double(s.cornerRadius) }, Double(f.model.unit * 24)),
                                   ("Gradient angle", { (s: AnnotationKit.BackgroundStyle) in
                                       if case .gradient(let g) = s.fill { return Double(g.angle) } else { return -1 } }, 360.0)] {
            let s = try #require(f.slider(label), "\(label)")
            let at = { (x: CGFloat) in CGPoint(x: s.trackRect.minX + s.trackRect.width * x, y: s.bounds.midY) }
            await PointerDriver.press(s, at: at(0.5), dragging: [at(0.8), at(0.25)])
            let v = try #require(f.style.map(read))
            #expect(abs(v - max * 0.25) < max * 0.02, "\(label) released at 25 %: \(v)")
        }
    }
}
