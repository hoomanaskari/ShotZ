import Combine
import Foundation

/// Live Screen Recording state for onboarding/Settings. Polls once a second
/// only between `startPolling()` and `stopPolling()` (while a window that
/// shows it is visible), never while idle (SPEC §9).
@MainActor public final class ScreenRecordingStatus: ObservableObject {
    @Published public private(set) var isGranted: Bool
    private var timer: Timer?
    private var clients = 0
    private let check: () -> Bool

    public init(check: @escaping () -> Bool = { Permissions.hasScreenRecording }) {
        self.check = check
        isGranted = check()
    }

    public var isPolling: Bool { timer != nil }

    public func refresh() {
        let now = check()
        if now != isGranted { isGranted = now }
    }

    /// Reference-counted: each visible window calls start once and stop once.
    public func startPolling() {
        clients += 1
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        timer.tolerance = 0.3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    public func stopPolling() {
        clients = max(0, clients - 1)
        guard clients == 0 else { return }
        timer?.invalidate()
        timer = nil
    }
}
