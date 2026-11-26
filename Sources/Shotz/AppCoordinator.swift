import os
import AnnotationEditor
import AnnotationKit
import AppKit
import AppShell
import CaptureKit
import QuickAccess
import ShotzCore

/// Builds the concrete objects and wires the capture flow (ARCHITECTURE §2):
/// hotkey → guard permission → engine.capture → history.add → quickAccess.present;
/// quickAccess.requestAnnotate → editor.openEditor(for:).
@MainActor final class AppCoordinator: QuickAccessDelegate {
    private let paths = ShotzPaths.default
    private let settings = SettingsStore()
    private let engine: CaptureEngine = SystemCaptureEngine()
    private let history: FileHistoryStore
    private let exporter: ExportService
    private let quickAccess: QuickAccessPresenting
    private let editor: AnnotationEditing
    private let hotkeys: HotkeyCenter
    private let statusItem: StatusItemController
    private let settingsWindow: SettingsWindowController
    private var isCapturing = false
    private var lastClosed: CaptureResult?
    private let log = ShotzLog.logger("App")

    init() {
        let paths = self.paths
        history = FileHistoryStore(paths: paths)
        exporter = DefaultExportService(paths: paths)
        quickAccess = QuickAccessController(settings: settings, exporter: exporter)
        let history = self.history
        editor = EditorCoordinator(settings: settings, exporter: exporter) { history.documentURL(for: $0) }
        hotkeys = HotkeyCenter(settings: settings, devHotkeys: HotkeyCenter.devHotkeysRequested())
        statusItem = StatusItemController(hotkeys: hotkeys)
        settingsWindow = SettingsWindowController(settings: settings)
    }

    func start() {
        do { try paths.createDirectories() } catch {
            log.error("Cannot create app folders: \(error.localizedDescription, privacy: .public)")
        }
        quickAccess.delegate = self

        hotkeys.onAction = { [weak self] action in self?.handle(action) }
        hotkeys.registerAll()
        if hotkeys.devHotkeys { log.info("Dev hotkeys active (⌃⌥⌘3/4/5)") }

        statusItem.isVisible = settings.showMenuBarIcon
        statusItem.onCapture = { [weak self] mode in self?.capture(mode) }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onOpenLastInEditor = { [weak self] in self?.openLastInEditor() }
        statusItem.onSelectHistoryItem = { [weak self] capture in self?.quickAccess.present(capture) }
        statusItem.onMenuWillOpen = { [weak self] in self?.refreshHistoryMenu() }
        settingsWindow.onChange = { [weak self] in
            guard let self else { return }
            self.statusItem.isVisible = self.settings.showMenuBarIcon
        }

        let retention = settings.historyRetention.interval
        Task {
            if let retention { await history.prune(olderThan: retention) }
            refreshHistoryMenu()
        }
        log.info("Shotz started")
        runDebugLaunchArguments(DebugLaunchArguments())
    }

    /// `--debug-present` / `--debug-edit`: exercise the stack and editor without Screen Recording.
    private func runDebugLaunchArguments(_ debug: DebugLaunchArguments) {
        guard !debug.isEmpty else { return }
        let options = settings.captureOptions(paths: paths)
        Task {
            for url in debug.present {
                do {
                    let result = try DebugCaptureImporter.importImage(at: url, options: options)
                    await history.add(result)
                    quickAccess.present(result)
                    log.info("Debug present \(url.lastPathComponent, privacy: .public)")
                } catch {
                    log.error("Debug present failed for \(url.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
                }
            }
            if !debug.present.isEmpty { refreshHistoryMenu() }
            if let edit = debug.edit {
                log.info("Debug edit \(edit.lastPathComponent, privacy: .public)")
                editor.openEditor(imageAt: edit)
            }
        }
    }

    func stop() {
        hotkeys.unregisterAll()
        quickAccess.dismissAll()
    }

    func openSettings() { settingsWindow.show() }

    // MARK: Flow

    private func handle(_ action: HotkeyAction) {
        if let mode = action.captureMode {
            capture(mode)
        } else if action == .restoreLastClosed, let last = lastClosed {
            lastClosed = nil
            quickAccess.present(last)
        }
    }

    func capture(_ mode: CaptureMode) {
        guard !isCapturing else { return } // SPEC §2: ignored while a capture runs
        guard Permissions.hasScreenRecording else {
            showPermissionHelp()
            return
        }
        isCapturing = true
        let options = settings.captureOptions(paths: paths)
        Task {
            defer { isCapturing = false }
            do {
                guard let result = try await engine.capture(mode, options: options) else { return }
                await history.add(result)
                refreshHistoryMenu()
                if settings.afterCaptureShowQuickAccess { quickAccess.present(result) }
                if settings.afterCaptureCopyToClipboard { try await exporter.copyToPasteboard(imageAt: result.fileURL) }
                if settings.afterCaptureSave {
                    _ = try await exporter.saveToExportFolder(imageAt: result.fileURL, suggestedName: result.displayName, askDestination: false)
                }
            } catch CaptureError.permissionDenied {
                showPermissionHelp()
            } catch CaptureError.busy {
                log.info("Capture ignored: busy")
            } catch {
                log.error("Capture failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func openLastInEditor() {
        Task {
            guard let last = await history.recent(limit: 1).first else { return }
            editor.openEditor(for: last)
        }
    }

    private func refreshHistoryMenu() {
        Task {
            let items = await history.recent(limit: 10)
            statusItem.updateHistory(items)
        }
    }

    /// TODO(engineer A): replace with the onboarding permission step (SPEC §8).
    private func showPermissionHelp() {
        log.notice("Screen Recording permission missing")
        let alert = NSAlert()
        alert.messageText = String(localized: "Shotz needs Screen Recording permission")
        alert.informativeText = String(localized: "Allow Shotz in System Settings ▸ Privacy & Security ▸ Screen & System Audio Recording, then try again.")
        alert.addButton(withTitle: String(localized: "Open System Settings"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openScreenRecordingSettings()
        }
    }

    // MARK: QuickAccessDelegate

    func quickAccess(requestAnnotate capture: CaptureResult) {
        editor.openEditor(for: capture)
    }

    func quickAccess(didClose capture: CaptureResult, deleteFile: Bool) {
        lastClosed = capture
        guard deleteFile else { return }
        Task {
            await history.remove(id: capture.id, deleteFile: true)
            refreshHistoryMenu()
        }
    }

    func quickAccess(didExport capture: CaptureResult, to url: URL) {
        log.info("Exported \(capture.displayName, privacy: .public) to \(url.lastPathComponent, privacy: .public)")
    }
}
