import ShotzCore
import AppKit
import AppShell

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var coordinator: AppCoordinator?
    private var termSource: DispatchSourceSignal?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Before anything reads settings or history: data from the pre-release
        // app.shotz.Shotz identity moves to com.pixelforty.shotz (not in test runs).
        LegacyDataMigration.runAtLaunch()
        // Owner-only data (0700 folders, 0600 files) for installs from before 0.1.2: once, off the main thread.
        let paths = ShotzPaths.default
        Task.detached(priority: .utility) {
            let changed = paths.repairPermissions()
            if changed > 0 { ShotzLog.logger("App").notice("Data permissions tightened on \(changed) items") }
        }
        let coordinator = AppCoordinator()
        self.coordinator = coordinator
        coordinator.start()
        installTermHandler()
    }

    /// SIGTERM (logout, `kill`, scripts/run.sh) quits through AppKit so the
    /// coordinator's clean shutdown runs.
    private func installTermHandler() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler {
            MainActor.assumeIsolated { NSApp.terminate(nil) }
        }
        source.resume()
        termSource = source
    }

    /// Launching Shotz again (Finder/Spotlight) opens Settings, so the app
    /// is reachable even with the menu-bar icon hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        coordinator?.handleReopen()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationWillTerminate(_ notification: Notification) {
        coordinator?.stop()
    }
}
