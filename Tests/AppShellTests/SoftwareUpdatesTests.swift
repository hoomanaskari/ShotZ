import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

/// Updates are production-only: ShotZ Dev and test runs never build an updater
/// (so never touch the network), and a build without a public key says so.
@MainActor
struct SoftwareUpdatesTests {
    let feed = "https://raw.githubusercontent.com/hoomanaskari/ShotZ/main/appcast.xml"
    let key = "AAAAC3NzaC1lZDI1NTE5AAAAIFakeTestKeyNotARealOne0000000000000000"

    @MainActor final class FakeUpdater: UpdaterBackend {
        var automaticallyChecks = true
        var lastCheckDate: Date? = Date(timeIntervalSince1970: 1_000)
        var checks = 0
        func checkForUpdates() { checks += 1 }
    }

    // MARK: Policy

    @Test func policyAllowsOnlyTheProductionAppOutsideTestRunsWithFeedAndKey() {
        let full: [String: Any] = [UpdatePolicy.feedKey: feed, UpdatePolicy.publicKeyKey: key]
        #expect(UpdatePolicy.decide(variant: .production, testRun: false, info: full) == .available)
        #expect(UpdatePolicy.decide(variant: .development, testRun: false, info: full) == .unavailable(.developmentApp))
        #expect(UpdatePolicy.decide(variant: .development, testRun: true, info: full) == .unavailable(.developmentApp))
        #expect(UpdatePolicy.decide(variant: .production, testRun: true, info: full) == .unavailable(.testRun))
    }

    @Test func noKeyMeansUpdatesUnavailable() {
        for key in [nil, "", "   "] as [String?] {
            var info: [String: Any] = [UpdatePolicy.feedKey: feed]
            if let key { info[UpdatePolicy.publicKeyKey] = key }
            #expect(UpdatePolicy.decide(variant: .production, testRun: false, info: info) == .unavailable(.noPublicKey))
        }
        #expect(UpdateUnavailableReason.noPublicKey.message.contains("signing key"))
    }

    @Test func feedMustBeHTTPS() {
        for feed in [nil, "", "http://example.com/appcast.xml", "not a url"] as [String?] {
            var info: [String: Any] = [UpdatePolicy.publicKeyKey: key]
            if let feed { info[UpdatePolicy.feedKey] = feed }
            #expect(UpdatePolicy.decide(variant: .production, testRun: false, info: info) == .unavailable(.noFeed))
        }
    }

    // MARK: Gating

    @Test func unavailableUpdatesNeverConstructTheUpdater() {
        for reason in [UpdateUnavailableReason.developmentApp, .testRun, .noFeed, .noPublicKey] {
            var built = 0
            let updates = SoftwareUpdates(availability: .unavailable(reason)) { _ in built += 1; return FakeUpdater() }
            #expect(built == 0)
            #expect(!updates.isAvailable)
            updates.checkForUpdates()        // harmless no-ops
            updates.setAutomaticallyChecks(true)
            #expect(!updates.automaticallyChecks)
        }
    }

    @Test func theUnitTestRunnerGetsNoUpdater() {
        // Production variant, not a test run, but no feed in the runner's bundle: no Sparkle.
        let updates = SoftwareUpdates.forThisApp()
        #expect(!updates.isAvailable)
        #expect(updates.availability == .unavailable(.noFeed))
    }

    @Test func availableUpdatesForwardToTheBackend() {
        let fake = FakeUpdater()
        var built = 0
        let updates = SoftwareUpdates(availability: .available) { _ in built += 1; return fake }
        #expect(built == 1)
        #expect(updates.isAvailable)
        #expect(updates.automaticallyChecks)
        #expect(updates.lastCheckDate == Date(timeIntervalSince1970: 1_000))
        updates.setAutomaticallyChecks(false)
        #expect(!fake.automaticallyChecks && !updates.automaticallyChecks)
        updates.noteUpdateWaiting("1.2.0")
        #expect(updates.pendingVersion == "1.2.0")
        updates.checkForUpdates()
        #expect(fake.checks == 1)
        #expect(updates.pendingVersion == nil)
        fake.lastCheckDate = Date(timeIntervalSince1970: 2_000)
        updates.noteSessionFinished()
        #expect(updates.lastCheckDate == Date(timeIntervalSince1970: 2_000))
    }

    @Test func statusMenuShowsCheckForUpdatesOnlyWhenAvailable() {
        let settings = SettingsStore(defaults: MemoryDefaults(), variant: .production)
        let menu = StatusItemController(hotkeys: HotkeyCenter(settings: settings, hotkeysEnabled: false, registrar: FakeRegistrar()))
        #expect(!menu.debugMenuDescription.contains("Check for Updates"))
        menu.updates = .preview(.unavailable(.noPublicKey))
        #expect(!menu.debugMenuDescription.contains("Check for Updates"))
        let updates = SoftwareUpdates.preview(.available)
        menu.updates = updates
        #expect(menu.debugMenuDescription.contains("Check for Updates…"))
        updates.noteUpdateWaiting("2.0")
        #expect(menu.debugMenuDescription.contains("Update Available (2.0)…"))
    }

    // MARK: Configuration in the repository

    /// The committed key and feed make the installed app's updates available. Reads the real
    /// Resources/SparklePublicKey.txt, so an emptied or damaged key file fails the suite.
    @Test func committedKeyAndFeedMakeUpdatesAvailable() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let key = try String(contentsOf: root.appending(path: "Resources/SparklePublicKey.txt"), encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        #expect(!key.isEmpty, "Resources/SparklePublicKey.txt is empty")
        #expect(Data(base64Encoded: key)?.count == 32, "not a base64 Ed25519 public key")   // what Sparkle expects
        var info = try #require(NSDictionary(contentsOf: root.appending(path: "Resources/Info.plist")) as? [String: Any])
        info[UpdatePolicy.publicKeyKey] = key   // as bundle.sh writes it
        #expect(UpdatePolicy.hasPublicKey(info))
        #expect(UpdatePolicy.decide(variant: .production, testRun: false, info: info) == .available)
        #expect(UpdatePolicy.decide(variant: .development, testRun: false, info: info) == .unavailable(.developmentApp))
        #expect(UpdatePolicy.decide(variant: .production, testRun: true, info: info) == .unavailable(.testRun))
    }

    @Test func infoPlistHasTheFeedAndNoInlineKey() throws {
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info = try #require(NSDictionary(contentsOf: root.appending(path: "Resources/Info.plist")) as? [String: Any])
        #expect(info[UpdatePolicy.feedKey] as? String == feed)
        #expect(info["SUEnableAutomaticChecks"] as? Bool == true)
        #expect(info[UpdatePolicy.publicKeyKey] == nil)   // filled by bundle.sh from SparklePublicKey.txt
        #expect(FileManager.default.fileExists(atPath: root.appending(path: "Resources/SparklePublicKey.txt").path(percentEncoded: false)))
    }
}

struct AppVersionTests {
    @Test func parsesValidVersions() throws {
        let v = try #require(AppVersion(marketing: "1.2.3", build: "45"))
        #expect(v.components == [1, 2, 3])
        #expect(v.build == 45)
        #expect(v.description == "1.2.3 (45)")
        #expect(AppVersion(marketing: "0.1", build: "1")?.components == [0, 1])
    }

    @Test func rejectsMalformedVersions() {
        for (m, b) in [("1", "1"), ("1.2.3.4", "1"), ("1..2", "1"), ("1.2.x", "1"), ("", "1"), ("1.2", "0"),
                       ("1.2", "-1"), ("1.2", "007"), ("1.2", "+1"), ("1.2", " 1"), ("1.2", "1.5"), ("v1.2", "1"), ("1.٢", "1")] {
            #expect(AppVersion(marketing: m, build: b) == nil, "\(m) (\(b))")
        }
    }

    @Test func readsTheInfoDictionaryAndTheRepositoryPlist() throws {
        #expect(AppVersion.from(infoDictionary: ["CFBundleShortVersionString": "2.0.1", "CFBundleVersion": "7"])?.description == "2.0.1 (7)")
        #expect(AppVersion.from(infoDictionary: [:]) == nil)
        #expect(AppVersion.displayString(nil).contains("not bundled"))
        let root = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let info = try #require(NSDictionary(contentsOf: root.appending(path: "Resources/Info.plist")) as? [String: Any])
        #expect(AppVersion.from(infoDictionary: info) != nil)   // the single source is always valid
    }
}
