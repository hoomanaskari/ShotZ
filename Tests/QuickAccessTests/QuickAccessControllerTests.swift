import Foundation
import Testing
@testable import QuickAccess
import ShotzCore

// TODO(engineer B): StackLayout tests.
@MainActor
struct QuickAccessControllerTests {
    @Test func conformsToPresenting() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShotzQATests-\(UUID().uuidString)"))
        let controller: QuickAccessPresenting = QuickAccessController(settings: SettingsStore(defaults: defaults), exporter: DefaultExportService())
        controller.dismissAll()
        #expect(controller.delegate == nil)
    }
}
