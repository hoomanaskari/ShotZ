import AnnotationKit
import AppKit
import Testing
@testable import AnnotationEditor
import ShotzTestSupport
@testable import ShotzUI

/// The options bar's sliders (opacity, corner radius, redaction strength) driven by real in-process
/// mouse events. Their handlers rebuild the bar on each final value, so before the 0.1.2 fix they
/// froze or jumped the same way as the Background panel's sliders.
@MainActor
struct OptionsBarSliderInteractionTests {
    static func bar(tool: ToolKind) -> (EditorModel, OptionsBarView, NSWindow) {
        let model = makeModel(tool: tool)
        let bar = OptionsBarView(model: model)
        let content = NSView(frame: CGRect(x: 0, y: 0, width: 1400, height: 120))
        bar.frame = CGRect(x: 0, y: 40, width: 1400, height: 44)
        bar.autoresizingMask = [.width]
        content.addSubview(bar)
        let window = PointerDriver.window(hosting: content, size: content.frame.size)
        bar.layoutSubtreeIfNeeded()
        return (model, bar, window)
    }

    static func slider(_ label: String, in bar: NSView) -> ShotzSlider? {
        PointerDriver.all(ShotzSlider.self, in: bar).first { $0.accessibilityLabel() == label }
    }

    /// Press at 50 %, drag to 80 % then back to 20 %: the setting follows and ends low.
    static func dragBackAndForth(_ label: String, tool: ToolKind, read: @escaping (ToolSettings) -> Double, range: ClosedRange<Double>) async throws {
        let (model, bar, window) = Self.bar(tool: tool)
        let s = try #require(Self.slider(label, in: bar), "\(label) slider in the options bar")
        let at = { (f: CGFloat) in CGPoint(x: s.trackRect.minX + s.trackRect.width * f, y: s.bounds.midY) }   // along the track
        var seen: [Double] = []
        await PointerDriver.press(s, at: at(0.5), dragging: [at(0.65), at(0.8), at(0.4), at(0.2)]) { _ in
            seen.append(read(model.settings(for: tool)))
        }
        let span = range.upperBound - range.lowerBound
        let final = read(model.settings(for: tool))
        #expect(final < range.lowerBound + span * 0.4, "\(label): after dragging back left it is \(final) (seen \(seen))")
        #expect(seen.allSatisfy { $0 < range.upperBound - span * 0.02 }, "\(label): never jumped to the maximum (seen \(seen))")
        _ = window
    }

    @Test func opacitySliderFollowsADrag() async throws {
        try await Self.dragBackAndForth("Opacity", tool: .rectangle, read: { Double($0.opacity) }, range: 0.1...1)
    }

    @Test func cornerRadiusSliderFollowsADrag() async throws {
        try await Self.dragBackAndForth("Corner radius", tool: .rectangle, read: { Double($0.cornerRadiusUnits) }, range: 0...12)
    }

    @Test func redactionStrengthSliderFollowsADrag() async throws {
        try await Self.dragBackAndForth("Strength", tool: .redact, read: { Double($0.redactMode.strength) }, range: 0.2...1)
    }
}
