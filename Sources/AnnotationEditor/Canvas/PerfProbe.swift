import os
import AnnotationKit
import AppKit
import QuartzCore

/// Opt-in performance logging (`SHOTZ_EDITOR_PERF=1`): during each drag it
/// records how long every document update took on the main thread and the
/// interval between displayed frames, then logs a summary when the drag ends.
@MainActor final class PerfProbe: NSObject {
    private let log: Logger
    private var link: CADisplayLink?
    private var updates: [Double] = []
    private var frames: [CFTimeInterval] = []
    private var lastFrame: CFTimeInterval?
    private var lastUpdate = Date.distantPast

    init(view: NSView, log: Logger) {
        self.log = log
        super.init()
        let link = view.displayLink(target: self, selector: #selector(tick(_:)))
        link.add(to: .main, forMode: .common)
        self.link = link
    }

    func recordUpdate(_ duration: Duration, reason: DocumentChange.Reason) {
        guard case .interactive = reason else { return }
        let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
        updates.append(ms)
        lastUpdate = Date()
    }

    /// The sharp re-render after a drag (final redactions, uncapped bitmaps).
    func recordFinish(_ duration: Duration) {
        let ms = Double(duration.components.attoseconds) / 1e15 + Double(duration.components.seconds) * 1000
        if ms > 0.5 { log.notice("PERF mouse-up finish \(ms, format: .fixed(precision: 2)) ms") }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let t = link.timestamp
        defer { lastFrame = t }
        if !updates.isEmpty, Date().timeIntervalSince(lastUpdate) < 0.25, let lastFrame {
            frames.append((t - lastFrame) * 1000)
        } else if !updates.isEmpty, Date().timeIntervalSince(lastUpdate) >= 0.25 {
            summarize()
        }
    }

    private func summarize() {
        let u = updates.sorted(), f = frames.sorted()
        func pct(_ a: [Double], _ p: Double) -> Double { a.isEmpty ? 0 : a[min(a.count - 1, Int(Double(a.count) * p))] }
        let avgFrame = f.isEmpty ? 0 : f.reduce(0, +) / Double(f.count)
        let slow = f.filter { $0 > 20 }.count
        log.notice("""
            PERF drag: \(u.count) updates, update ms median \(pct(u, 0.5), format: .fixed(precision: 2)) p95 \(pct(u, 0.95), format: .fixed(precision: 2)) max \(u.last ?? 0, format: .fixed(precision: 2)); \
            \(f.count) frames, avg \(avgFrame, format: .fixed(precision: 2)) ms (\(avgFrame > 0 ? 1000 / avgFrame : 0, format: .fixed(precision: 1)) fps), p95 \(pct(f, 0.95), format: .fixed(precision: 2)) ms, frames over 20 ms: \(slow)
            """)
        updates = []
        frames = []
    }
}
