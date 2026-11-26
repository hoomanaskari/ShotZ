import Foundation
import Testing
import ShotzTestSupport
@testable import ShotzCore

/// The production app ignores every debug hook; ShotZ Dev honours them (DebugHooks is the one gate).
struct DebugHooksTests {
    let exe = "/Applications/ShotZ.app/Contents/MacOS/ShotZ"

    @Test func onlyTheDevelopmentAppHonoursHooks() {
        #expect(DebugHooks.allowed(variant: .development))
        #expect(!DebugHooks.allowed(variant: .production))
        #expect(!DebugHooks.isAllowed)   // the unit-test runner counts as production
    }

    @Test func productionSeesNoLaunchArgumentHook() {
        for hook in DebugHooks.argumentHooks {
            let all = [exe, hook, "/tmp/x.png"]
            #expect(DebugHooks.arguments(all, allowed: false) == [exe], "\(hook)")
            #expect(DebugHooks.arguments(all, allowed: true) == all, "\(hook)")
            // So production is never a hermetic test run and never drops its shortcuts.
            #expect(!AppVariant.isTestRun(arguments: DebugHooks.arguments(all, allowed: false), environment: [:]), "\(hook)")
            #expect(AppVariant.isTestRun(arguments: DebugHooks.arguments(all, allowed: true), environment: [:]), "\(hook)")
        }
        let selfTest = [exe, "-QuickAccessSelfTest", "/tmp/r"]
        #expect(!AppVariant.isTestRun(arguments: DebugHooks.arguments(selfTest, allowed: false), environment: [:]))
        #expect(AppVariant.isTestRun(arguments: DebugHooks.arguments(selfTest, allowed: true), environment: [:]))
    }

    @Test func productionSeesNoEnvironmentHook() {
        for key in DebugHooks.environmentHooks {
            let env = [key: "/tmp/script", "PATH": "/usr/bin"]
            #expect(DebugHooks.environment(env, allowed: false) == ["PATH": "/usr/bin"], "\(key)")
            #expect(DebugHooks.environment(env, allowed: true) == env, "\(key)")
        }
        let script = ["SHOTZ_EDITOR_SCRIPT": "/tmp/s"]
        #expect(!AppVariant.isTestRun(arguments: [exe], environment: DebugHooks.environment(script, allowed: false)))
        #expect(AppVariant.isTestRun(arguments: [exe], environment: DebugHooks.environment(script, allowed: true)))
    }

    @Test func productionReadsNoDebugPreference() throws {
        let defaults = MemoryDefaults()
        for key in DebugHooks.defaultsHooks {
            defaults.set("YES", forKey: key)
            #expect(!DebugHooks.bool(key, defaults: defaults, allowed: false), "\(key)")
            #expect(DebugHooks.string(key, defaults: defaults, allowed: false) == nil, "\(key)")
            #expect(DebugHooks.bool(key, defaults: defaults, allowed: true), "\(key)")
            #expect(DebugHooks.string(key, defaults: defaults, allowed: true) == "YES", "\(key)")
        }
    }

    /// `-general.exportFolder /tmp/x` style overrides: production empties the argument domain at
    /// launch (checked through the injected step; volatile domains are process-wide, so the test
    /// never touches the real one), and logs hook names, never values.
    @Test func productionDropsArgumentDomainOverrides() {
        let launch = [exe, "-general.exportFolder", "/tmp/elsewhere", "--debug-present", "/tmp/a.png"]
        let env = ["SHOTZ_EDITOR_PERF": "1", "HOME": "/Users/x"]
        var cleared = 0
        let ignored = DebugHooks.applyAtLaunch(allowed: false, arguments: launch, environment: env) { cleared += 1 }
        #expect(cleared == 1)
        #expect(ignored == ["--debug-present", "-general.exportFolder", "SHOTZ_EDITOR_PERF"])
        #expect(!ignored.contains { $0.contains("/") })
        let honoured = DebugHooks.applyAtLaunch(allowed: true, arguments: launch, environment: env) { cleared += 1 }
        #expect(cleared == 1)   // ShotZ Dev keeps its argument domain
        #expect(honoured.isEmpty)
    }
}
