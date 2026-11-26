import Foundation
import Testing
@testable import AnnotationEditor
import ShotzCore

// TODO(engineer D): tool and canvas tests.
@MainActor
struct EditorCoordinatorTests {
    @Test func conformsToAnnotationEditing() throws {
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        let editor: AnnotationEditing = EditorCoordinator(
            settings: SettingsStore(defaults: defaults), exporter: DefaultExportService(),
            documentURL: { URL(filePath: "/tmp/\($0.uuidString).json") }
        )
        _ = editor
    }
}
