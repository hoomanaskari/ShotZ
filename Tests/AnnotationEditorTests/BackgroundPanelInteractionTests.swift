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
        func slider(_ label: String) -> ShotzSlider? {
            PointerDriver.all(ShotzSlider.self, in: panel).first { $0.accessibilityLabel() == label }
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
}
