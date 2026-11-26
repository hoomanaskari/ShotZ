import os
import AppKit
import AppShell
import ShotzCore

/// `--debug-snapshot-ui <dir>`: renders each Settings tab, each onboarding
/// step and the status item to PNGs (drawn in-process, so no Screen
/// Recording permission is involved), and writes the status menu as text.
@MainActor enum DebugUISnapshot {
    static func run(_ coordinator: AppCoordinator, into dir: URL) async {
        let log = ShotzLog.logger("App")
        do { try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) } catch {
            log.error("Snapshot dir: \(error.localizedDescription, privacy: .public)")
            return
        }
        for step in OnboardingStep.allCases {
            coordinator.onboarding.show(step: step)
            await settle()
            write(coordinator.onboarding.debugWindow, to: dir.appending(path: "onboarding-\(step.rawValue)-\(step).png"))
        }
        coordinator.onboarding.debugWindow?.close()
        for tab in SettingsTab.allCases {
            coordinator.openSettings(tab: tab)
            await settle()
            write(coordinator.settingsWindow.debugWindow, to: dir.appending(path: "settings-\(tab.rawValue).png"))
        }
        if let button = coordinator.statusItem.debugButton { write(view: button, to: dir.appending(path: "status-item.png")) }
        do {
            try coordinator.statusItem.debugMenuDescription.write(to: dir.appending(path: "status-menu.txt"), atomically: true, encoding: .utf8)
        } catch {
            log.error("Menu dump: \(error.localizedDescription, privacy: .public)")
        }
        log.info("UI snapshots written to \(dir.path(percentEncoded: false), privacy: .public)")
    }

    private static func settle() async {
        try? await Task.sleep(for: .milliseconds(700))   // let SwiftUI lay out; a cancelled sleep is harmless
    }

    private static func write(_ window: NSWindow?, to url: URL) {
        guard let view = window?.contentView?.superview ?? window?.contentView else { return }
        write(view: view, to: url)
    }

    private static func write(view: NSView, to url: URL) {
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        guard let data = rep.representation(using: .png, properties: [:]) else { return }
        do { try data.write(to: url) } catch {
            ShotzLog.logger("App").error("Snapshot write: \(error.localizedDescription, privacy: .public)")
        }
    }
}
