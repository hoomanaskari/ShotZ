import os
import AppKit
import AppShell
import ShotzCore

/// `--debug-snapshot-ui <dir>`: renders each Settings tab and onboarding step
/// off screen (nothing is shown, Shotz is not activated), the status item if
/// visible, and writes the status menu as text.
@MainActor enum DebugUISnapshot {
    static func run(_ coordinator: AppCoordinator, into dir: URL) async {
        let log = ShotzLog.logger("App")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log.error("Snapshot dir: \(error.localizedDescription, privacy: .public)")
            return
        }
        // Rendered off screen: nothing is shown and Shotz is never activated.
        for step in OnboardingStep.allCases {
            write(await coordinator.onboarding.debugRender(step: step), to: dir.appending(path: "onboarding-\(step.rawValue)-\(step).png"))
        }
        for tab in SettingsTab.allCases {
            write(await coordinator.settingsWindow.debugRender(tab: tab), to: dir.appending(path: "settings-\(tab.rawValue).png"))
        }
        if let button = coordinator.statusItem.debugButton { write(view: button, to: dir.appending(path: "status-item.png")) }
        do {
            try coordinator.statusItem.debugMenuDescription.write(to: dir.appending(path: "status-menu.txt"), atomically: true, encoding: .utf8)
        } catch {
            log.error("Menu dump: \(error.localizedDescription, privacy: .public)")
        }
        log.info("UI snapshots written to \(dir.path(percentEncoded: false), privacy: .public)")
    }

    private static func write(_ data: Data?, to url: URL) {
        guard let data else { return }
        do { try data.write(to: url) } catch {
            ShotzLog.logger("App").error("Snapshot write: \(error.localizedDescription, privacy: .public)")
        }
    }

    private static func write(view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        write(rep.representation(using: .png, properties: [:]), to: url)
    }
}
