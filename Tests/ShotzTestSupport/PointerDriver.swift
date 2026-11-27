import AppKit
import ShotzUI

/// Drives real controls with real `NSEvent` mouse sequences, in-process only (never CGEvent, never
/// system-wide), the way AppKit delivers them to a window that is not on screen:
///
/// - mouse-down: hit-test the window's content at the event's window location and call the hit
///   view's `mouseDown(with:)`, as `NSWindow.sendEvent` does (AppKit drops events sent to a window
///   that is not on screen, and tests never show windows);
/// - drags and mouse-up: handed to the control's own tracking loop through
///   `ShotzControlView.nextTrackingEvent`. Before returning each event the driver spins the main run
///   loop in `.eventTracking` mode, as `NSWindow.nextEvent(matching:)` does while it waits, so work
///   the app queued on the main queue (async commits, rebuilds) runs mid-drag exactly as in the app.
///
/// All points are given in the control's coordinates at the time of the mouse-down and converted to
/// window coordinates up front, like a real pointer whose position doesn't follow a rebuilt view.
///
/// The interaction runs from a run-loop timer, as AppKit delivers events from its run loop: a test
/// body (a main-queue job) can't let main-queue work run inside it, but a run-loop callback can, so
/// only this way does work the app queued with `DispatchQueue.main.async` run during the drag.
@MainActor
public enum PointerDriver {
    /// A point inside `control` at `fraction` of its width (vertically centred).
    public static func point(_ control: NSView, x fraction: CGFloat) -> CGPoint {
        CGPoint(x: control.bounds.minX + control.bounds.width * fraction, y: control.bounds.midY)
    }

    /// A press at `down`, drags through `drags`, release at the last drag point (or at `down`).
    /// `afterEach(i)` runs after event `i` was processed (0 = the mouse-down, then each drag; the
    /// mouse-up comes last), so tests can assert intermediate values.
    public static func press(_ control: NSView, at down: CGPoint, dragging drags: [CGPoint] = [],
                             afterEach: ((Int) -> Void)? = nil) async {
        let job = Job(control: control, down: down, drags: drags, afterEach: afterEach)
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let timer = Timer(timeInterval: 0, repeats: false) { _ in
                MainActor.assumeIsolated { deliver(job.control, at: job.down, dragging: job.drags, afterEach: job.afterEach) }
                done.resume()
            }
            RunLoop.main.add(timer, forMode: .common)
        }
        await settleAsync()
    }

    private static func deliver(_ control: NSView, at down: CGPoint, dragging drags: [CGPoint], afterEach: ((Int) -> Void)?) {
        guard let window = control.window, let content = window.contentView else { return }
        let toWindow = { (p: CGPoint) in control.convert(p, to: nil) }
        let downEvent = mouse(.leftMouseDown, at: toWindow(down), in: window)
        var queue = drags.map { mouse(.leftMouseDragged, at: toWindow($0), in: window) }
        queue.append(mouse(.leftMouseUp, at: toWindow(drags.last ?? down), in: window))
        var delivered = 0
        let saved = ShotzControlView.nextTrackingEvent
        ShotzControlView.nextTrackingEvent = { _ in
            afterEach?(delivered)
            delivered += 1
            // What AppKit's nextEvent does while waiting: main-queue work runs in tracking mode.
            RunLoop.main.run(mode: .eventTracking, before: Date(timeIntervalSinceNow: 0.01))
            return queue.isEmpty ? nil : queue.removeFirst()
        }
        defer { ShotzControlView.nextTrackingEvent = saved }
        let hitPoint = content.superview?.convert(downEvent.locationInWindow, from: nil) ?? downEvent.locationInWindow
        guard let hit = content.hitTest(hitPoint) else { return }
        hit.mouseDown(with: downEvent)
    }

    /// A single click at `point` (in the control's coordinates).
    public static func click(_ control: NSView, at point: CGPoint) async { await press(control, at: point) }

    /// Lets main-queue work queued by the interaction finish (async commits and rebuilds).
    public static func settleAsync() async {
        for _ in 0..<3 { try? await Task.sleep(for: .milliseconds(10)); await Task.yield() }
    }

    public static func mouse(_ type: NSEvent.EventType, at p: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    /// An off-screen window (never ordered in) hosting `view` at `size`, laid out.
    public static func window(hosting view: NSView, size: CGSize) -> NSWindow {
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -20_000, y: -20_000), size: size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        view.layoutSubtreeIfNeeded()
        return window
    }

    /// Every subview of `root` of type `T`, depth first.
    public static func all<T: NSView>(_ type: T.Type, in root: NSView) -> [T] {
        root.subviews.flatMap { (($0 as? T).map { [$0] } ?? []) + all(type, in: $0) }
    }

    /// The interaction's inputs, carried into the timer callback (main thread only).
    private final class Job: @unchecked Sendable {
        let control: NSView, down: CGPoint, drags: [CGPoint], afterEach: ((Int) -> Void)?
        init(control: NSView, down: CGPoint, drags: [CGPoint], afterEach: ((Int) -> Void)?) {
            self.control = control; self.down = down; self.drags = drags; self.afterEach = afterEach
        }
    }
}
