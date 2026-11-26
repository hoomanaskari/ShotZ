import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

/// The Screen Recording step's note about two look-alike ShotZ entries in System Settings.
@MainActor
struct OnboardingDuplicateEntryTests {
    func model(migrated: Bool) throws -> (OnboardingModel, String) {
        let suite = "ShotzOnboardingNote-\(UUID().uuidString)"
        let settings = SettingsStore(defaults: MemoryDefaults(), variant: .production)
        let model = OnboardingModel(
            settings: settings,
            hotkeys: HotkeyCenter(settings: settings, hotkeysEnabled: false, registrar: FakeRegistrar()),
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/ShotZ.app"), variant: .production),
            screenRecording: ScreenRecordingStatus(check: { false }),
            previousIdentityMigrated: migrated
        )
        return (model, suite)
    }

    @Test func showsOnlyAfterTheIdentityChangeWhilePermissionIsMissing() throws {
        let (migrated, _) = try model(migrated: true)
        let (fresh, _) = try model(migrated: false)
        #expect(migrated.showsDuplicateEntryNote(granted: false))
        #expect(!migrated.showsDuplicateEntryNote(granted: true))
        #expect(!fresh.showsDuplicateEntryNote(granted: false))
        #expect(!fresh.showsDuplicateEntryNote(granted: true))
    }

    @Test func migrationMarkerDecidesWhetherThisMacChangedIdentity() throws {
        let base = FileManager.default.temporaryDirectory.appending(path: "ShotzMarker-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: base) }
        let old = base.appending(path: "Shotz", directoryHint: .isDirectory)
        let migration = LegacyDataMigration(oldRoot: old, newRoot: base.appending(path: "com.pixelforty.shotz"),
                                            oldDomain: { nil }, newDefaults: .standard, newDomainName: "unused")
        #expect(!migration.hasMigrated)                       // no old folder (fresh install)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        #expect(!migration.hasMigrated)                       // old data, not migrated yet
        try Data("moved".utf8).write(to: old.appending(path: LegacyDataMigration.markerFileName))
        #expect(migration.hasMigrated)
    }
}
