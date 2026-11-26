import Foundation
import Testing
import ShotzTestSupport
@testable import QuickAccess
import ShotzCore

@MainActor
struct QuickAccessControllerTests {
    @Test func conformsToPresenting() throws {
        let defaults = MemoryDefaults()
        let controller: QuickAccessPresenting = QuickAccessController(settings: SettingsStore(defaults: defaults), exporter: DefaultExportService())
        controller.dismissAll()
        #expect(controller.delegate == nil)
    }

    @Test func pausableTimer() async throws {
        var fired = 0
        let timer = AutoCloseTimer(seconds: 0.2) { fired += 1 }
        timer.start()
        timer.pause()
        #expect(!timer.isRunning)
        try await Task.sleep(for: .milliseconds(300))
        #expect(fired == 0)
        timer.cancel()
        #expect(fired == 0)
    }
}
