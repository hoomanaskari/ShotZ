import Carbon.HIToolbox
import Foundation
import os
import ShotzCore

/// Where `HotkeyCenter` registers shortcuts. The Carbon implementation is the
/// real one; tests inject a fake so they can simulate failures and never
/// register global shortcuts that could collide with a running ShotZ.
@MainActor protocol HotkeyRegistrar: AnyObject {
    /// Registers `combo` under `id`; returns `noErr` or the Carbon status.
    func register(_ combo: KeyCombo, id: UInt32) -> OSStatus
    func unregister(id: UInt32)
    /// True only for the registrar that talks to the system (Carbon).
    var isSystemRegistrar: Bool { get }
}

extension HotkeyRegistrar {
    var isSystemRegistrar: Bool { false }
}

/// True in unit-test processes (`swift test`: XCTest or the swift-testing helper).
/// Such processes run on the owner's Mac next to the real ShotZ, so they must never
/// touch system-wide state like global shortcuts.
enum TestProcess {
    static let isUnitTestRunner: Bool = detect(
        processName: ProcessInfo.processInfo.processName,
        environment: ProcessInfo.processInfo.environment,
        bundlePaths: Bundle.allBundles.map(\.bundlePath)
    )

    static func detect(processName: String, environment: [String: String], bundlePaths: [String]) -> Bool {
        let name = processName.lowercased()
        return name == "xctest" || name.hasPrefix("swiftpm-testing-helper")
            || environment["XCTestConfigurationFilePath"] != nil
            || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
            || bundlePaths.contains { $0.hasSuffix(".xctest") }
    }
}

@MainActor final class CarbonHotkeyRegistrar: HotkeyRegistrar {
    /// Returned instead of registering in unit tests and test runs ('SZno').
    static let refusedStatus = OSStatus(bitPattern: 0x535A_6E6F)
    /// Calls that reached `RegisterEventHotKey` in this process. Always 0 in unit tests.
    private(set) static var systemRegistrations = 0
    private static var loggedRefusal = false

    /// Unit-test processes and hermetic test runs never register global shortcuts.
    static var refusesInThisProcess: Bool { TestProcess.isUnitTestRunner || AppVariant.isTestRun }

    private var refs: [UInt32: EventHotKeyRef] = [:]

    var isSystemRegistrar: Bool { true }

    func register(_ combo: KeyCombo, id: UInt32) -> OSStatus {
        guard !Self.refusesInThisProcess else {
            if !Self.loggedRefusal {
                Self.loggedRefusal = true
                ShotzLog.logger("AppShell").notice("Hotkeys: refusing to register global shortcuts in a test process")
            }
            return Self.refusedStatus
        }
        unregister(id: id)
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: HotkeyCenter.signature, id: id)
        Self.systemRegistrations += 1
        let status = RegisterEventHotKey(
            combo.keyCode, HotkeyCenter.carbonModifiers(combo.modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref
        )
        if status == noErr, let ref {
            refs[id] = ref
            return noErr
        }
        return status == noErr ? OSStatus(eventInternalErr) : status
    }

    func unregister(id: UInt32) {
        if let ref = refs.removeValue(forKey: id) { UnregisterEventHotKey(ref) }
    }
}
