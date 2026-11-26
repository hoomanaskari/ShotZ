import Foundation
import ShotzCore

/// Runs history pruning once a day (SPEC §6) through the system's background
/// activity scheduler, so there is no app timer ticking while idle (SPEC §9).
@MainActor public final class HistoryPruneScheduler {
    private let scheduler: NSBackgroundActivityScheduler
    private let work: @Sendable () async -> Void

    /// `work` is called roughly every `interval` seconds while the app runs.
    public init(interval: TimeInterval = 86_400, work: @escaping @Sendable () async -> Void) {
        scheduler = NSBackgroundActivityScheduler(identifier: "app.shotz.Shotz.history-prune")
        scheduler.repeats = true
        scheduler.interval = interval
        scheduler.tolerance = interval / 4
        scheduler.qualityOfService = .background
        self.work = work
    }

    public func start() {
        let work = self.work
        scheduler.schedule { completion in
            // The scheduler waits for `completion`; finishing after the async
            // work keeps two prunes from overlapping.
            let done = UncheckedCompletion(completion)
            Task {
                await work()
                done.call()
            }
        }
    }

    public func stop() {
        scheduler.invalidate()
    }
}

/// Wraps the scheduler's completion handler so it can cross into a Task.
/// Unchecked: the handler is documented as callable from any thread, once.
private struct UncheckedCompletion: @unchecked Sendable {
    let handler: NSBackgroundActivityScheduler.CompletionHandler
    init(_ handler: @escaping NSBackgroundActivityScheduler.CompletionHandler) { self.handler = handler }
    func call() { handler(.finished) }
}
