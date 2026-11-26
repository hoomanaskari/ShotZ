import Carbon.HIToolbox
import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

/// Unit tests run on the owner's Mac next to the real ShotZ: they must never register
/// global shortcuts or install a Carbon event handler.
@MainActor
struct TestProcessGuardTests {
    @Test func thisProcessIsRecognisedAsAUnitTestRunner() {
        #expect(TestProcess.isUnitTestRunner)
        #expect(CarbonHotkeyRegistrar.refusesInThisProcess)
    }

    @Test func detection() {
        #expect(TestProcess.detect(processName: "swiftpm-testing-helper", environment: [:], bundlePaths: []))
        #expect(TestProcess.detect(processName: "xctest", environment: [:], bundlePaths: []))
        #expect(TestProcess.detect(processName: "x", environment: ["XCTestConfigurationFilePath": "/t"], bundlePaths: []))
        #expect(TestProcess.detect(processName: "x", environment: [:], bundlePaths: ["/b/ShotzPackageTests.xctest"]))
        #expect(!TestProcess.detect(processName: "ShotZ", environment: [:], bundlePaths: ["/Applications/ShotZ.app"]))
    }

    @Test func theRealRegistrarRefusesAndNeverReachesCarbon() {
        let registrar = CarbonHotkeyRegistrar()
        #expect(registrar.register(.defaultArea, id: 99) == CarbonHotkeyRegistrar.refusedStatus)
        #expect(CarbonHotkeyRegistrar.systemRegistrations == 0)
    }

    @Test func aStartedCenterWithTheRealRegistrarRegistersNothing() throws {
        let settings = SettingsStore(defaults: MemoryDefaults(), variant: .production)
        let center = HotkeyCenter(settings: settings, hotkeysEnabled: true)   // the app's convenience init
        center.start()
        defer { center.shutdown() }
        #expect(center.registeredActions.isEmpty)
        #expect(Set(center.registrationFailures.values) == [CarbonHotkeyRegistrar.refusedStatus])
        #expect(!center.hasEventHandler)
        #expect(CarbonHotkeyRegistrar.systemRegistrations == 0)
    }

    /// Process-wide: no test in this run has reached RegisterEventHotKey (the guard makes it
    /// impossible; this fails loudly if the guard is ever removed and a test leaks).
    @Test func noTestRegisteredThroughTheSystem() {
        #expect(CarbonHotkeyRegistrar.systemRegistrations == 0)
    }

    /// Every HotkeyCenter built in the tests injects a fake registrar.
    @Test func testsAlwaysInjectAFakeRegistrar() throws {
        let tests = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let files = try #require(FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" && $0.lastPathComponent != "TestProcessGuardTests.swift" }
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            for line in source.split(separator: "\n") where line.contains("HotkeyCenter(settings:") {
                #expect(line.contains("registrar:"), "\(file.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
            }
        }
    }
}

struct TestProcessAppBundleTests {
    /// A real app bundle is never treated as a unit-test runner, whatever its environment says.
    @Test func appBundlesIgnoreTestEnvironment() {
        #expect(!TestProcess.detect(processName: "ShotZ", environment: ["XCTestConfigurationFilePath": "/x"],
                                    bundlePaths: ["/x/Foo.xctest"], mainBundlePath: "/Applications/ShotZ.app"))
        #expect(TestProcess.detect(processName: "x", environment: ["XCTestConfigurationFilePath": "/x"], bundlePaths: [],
                                   mainBundlePath: "/usr/bin"))
    }
}
