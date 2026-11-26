import AppKit

/// Calls back on the first display refresh after now, to measure when a card
/// actually reaches the screen (logged for the 150 ms target, SPEC §3.5).
@MainActor final class FrameProbe: NSObject {
    private var link: CADisplayLink?
    private let onFrame: () -> Void
    private static var live: Set<FrameProbe> = []

    private init(onFrame: @escaping () -> Void) { self.onFrame = onFrame }

    static func measure(in view: NSView, _ onFrame: @escaping () -> Void) {
        let probe = FrameProbe(onFrame: onFrame)
        let link = view.displayLink(target: probe, selector: #selector(tick))
        probe.link = link
        live.insert(probe)
        link.add(to: .main, forMode: .common)
    }

    @objc private func tick() {
        link?.invalidate()
        link = nil
        Self.live.remove(self)
        onFrame()
    }
}
