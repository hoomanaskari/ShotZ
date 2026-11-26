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
        // The menu as the installed app shows it (with "Check for Updates…"); never contacts the network.
        coordinator.statusItem.updates = .preview(.available)
        // Rendered off screen: nothing is shown and Shotz is never activated.
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            for scale in [1.0, 2.0] {
                let suffix = "\(name)@\(Int(scale))x"
                for step in OnboardingStep.allCases {
                    write(await coordinator.onboarding.debugRender(step: step, appearance: appearance, scale: scale),
                          to: dir.appending(path: "onboarding-\(step.rawValue)-\(step)-\(suffix).png"))
                }
                for tab in SettingsTab.allCases {
                    write(await coordinator.settingsWindow.debugRender(tab: tab, appearance: appearance, scale: scale),
                          to: dir.appending(path: "settings-\(tab.rawValue)-\(suffix).png"))
                }
                // The updates section without a signing key yet (what the first builds show).
                write(await coordinator.settingsWindow.debugRender(tab: .advanced, appearance: appearance, scale: scale,
                                                                   updates: .preview(.unavailable(.noPublicKey))),
                      to: dir.appending(path: "settings-advanced-nokey-\(suffix).png"))
                write(await coordinator.statusItem.debugMenuSnapshot(appearance: appearance, scale: scale),
                      to: dir.appending(path: "status-menu-\(suffix).png"))
            }
        }
        let tabIcons: [ShellIcon] = [.general, .shortcuts, .quickAccess, .capture, .editor, .advanced]
        write(ShellIcon.debugToolbarStrip(tabIcons, scale: 1), to: dir.appending(path: "toolbar-icons-1x.png"))
        write(ShellIcon.debugToolbarStrip(tabIcons, scale: 2), to: dir.appending(path: "toolbar-icons-2x.png"))
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
