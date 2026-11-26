import Foundation

/// A pausable one-shot countdown (SPEC §4.1 auto-close). Runs only while a
/// card is waiting; no timers exist with an empty stack.
@MainActor final class AutoCloseTimer {
    private var remaining: TimeInterval
    private var deadline: Date?
    private var timer: Timer?
    private let onFire: @MainActor () -> Void

    /// Never resume with less than this, so a card doesn't vanish the instant the pointer leaves.
    static let minimumAfterResume: TimeInterval = 1.5

    init(seconds: TimeInterval, onFire: @escaping @MainActor () -> Void) {
        remaining = seconds
        self.onFire = onFire
    }

    var isRunning: Bool { timer != nil }

    func start() {
        guard timer == nil else { return }
        deadline = Date().addingTimeInterval(remaining)
        let t = Timer(timeInterval: remaining, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func pause() {
        guard let timer, let deadline else { return }
        timer.invalidate()
        self.timer = nil
        remaining = max(Self.minimumAfterResume, deadline.timeIntervalSinceNow)
        self.deadline = nil
    }

    func cancel() {
        timer?.invalidate()
        timer = nil
    }

    private func fire() {
        timer = nil
        onFire()
    }
}
