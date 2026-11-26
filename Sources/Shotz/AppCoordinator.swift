import os
import AnnotationEditor
import AnnotationKit
import AppKit
import AppShell
import CaptureKit
import Combine
import QuickAccess
import ShotzCore

/// Builds the concrete objects and wires the capture flow (ARCHITECTURE §2):
/// hotkey → guard permission → engine.capture → history.add → quickAccess.present;
/// quickAccess.requestAnnotate → editor.openEditor(for:); editor close → card
/// returns to the stack (SPEC §4.6, via `CaptureEditingFlow`).
@MainActor final class AppCoordinator: QuickAccessDelegate {
    let paths = ShotzPaths.default
    let settings = SettingsStore()
    let engine: CaptureEngine = SystemCaptureEngine()
    let history: FileHistoryStore
    let exporter: ExportService
    let quickAccess: QuickAccessPresenting
    let editor: AnnotationEditing
    let hotkeys: HotkeyCenter
    let statusItem: StatusItemController
    let loginItem: LoginItemController
    let screenRecording = ScreenRecordingStatus()
    let editingFlow: CaptureEditingFlow
    private(set) var settingsWindow: SettingsWindowController!
    private(set) var onboarding: OnboardingWindowController!
    private var pruneScheduler: HistoryPruneScheduler?
    private var settingsObserver: AnyCancellable?
    private var lastAppliedRetention: HistoryRetention?

    var captureTask: Task<Void, Never>?
    var isCapturing: Bool { captureTask != nil }
    /// Recently closed cards, most recent last (for "Restore Last Closed Card").
    var closedCards: [CaptureResult] = []
    static let closedCardsLimit = 20
    let log = ShotzLog.logger("App")

    init() {
        let paths = self.paths
        history = FileHistoryStore(paths: paths)
        exporter = DefaultExportService(paths: paths)
        quickAccess = QuickAccessController(settings: settings, exporter: exporter)
        let history = self.history
        // Export memory: the editor's Save overwrites the export recorded in
        // history, and records new ones, across reopen (SPEC §5.5).
        editor = EditorCoordinator(
            settings: settings,
            exporter: exporter,
            documentURL: { history.documentURL(for: $0) },
            previousExport: { await history.exportURL(for: $0) },
            recordExport: { await history.markExported(id: $0, url: $1) }
        )
        editingFlow = CaptureEditingFlow(quickAccess: quickAccess, editor: editor) { id in
            let url = history.renderedURL(for: id)
            return FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) ? url : nil
        }
        let testRun = HotkeyCenter.hotkeysDisabledRequested()
        hotkeys = HotkeyCenter(settings: settings, hotkeysEnabled: !testRun)
        statusItem = StatusItemController(hotkeys: hotkeys)
        loginItem = LoginItemController(settings: settings, testRun: testRun)
        onboarding = OnboardingWindowController(
            settings: settings, hotkeys: hotkeys, loginItem: loginItem, screenRecording: screenRecording
        )
        settingsWindow = SettingsWindowController(context: SettingsContext(
            settings: settings,
            hotkeys: hotkeys,
            loginItem: loginItem,
            screenRecording: screenRecording,
            clearHistory: { [weak self] in await self?.clearHistory() },
            showOnboarding: { [weak self] permissionStep in
                self?.onboarding.show(step: permissionStep ? .screenRecording : .welcome)
            }
        ))
    }

    func start() {
        let variant = AppVariant.current
        log.notice("Variant: \(variant.rawValue, privacy: .public) (\(variant.displayName, privacy: .public), \(variant.bundleIdentifier, privacy: .public), data \(self.paths.root.path(percentEncoded: false), privacy: .public))")
        do { try paths.createDirectories() } catch {
            log.error("Cannot create app folders: \(error.localizedDescription, privacy: .public)")
        }
        quickAccess.delegate = self
        editor.delegate = editingFlow
        editingFlow.didPresent = { [weak self] capture in self?.closedCards.removeAll { $0.id == capture.id } }

        hotkeys.onAction = { [weak self] action in self?.handle(action) }
        hotkeys.start()
        log.notice("Hotkeys: \(self.hotkeys.hotkeysEnabled ? "stored shortcuts" : "off for this run (--no-hotkeys)", privacy: .public)")

        statusItem.onCapture = { [weak self] mode in self?.capture(mode) }
        statusItem.onOpenSettings = { [weak self] in self?.openSettings() }
        statusItem.onOpenLastInEditor = { [weak self] in self?.openLastInEditor() }
        statusItem.onRestoreLastClosed = { [weak self] in self?.restoreLastClosed() }
        statusItem.canRestoreLastClosed = { [weak self] in self?.canRestoreLastClosed ?? false }
        statusItem.onSelectHistoryItem = { [weak self] capture in self?.reopenFromHistory(capture) }
        statusItem.onMenuWillOpen = { [weak self] in self?.refreshHistoryMenu() }

        loginItem.applyAtLaunch()
        applySettings()
        // objectWillChange fires before the value is stored: apply on the next turn.
        settingsObserver = settings.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.applySettings() } }

        startHistoryPruning()
        log.info("Shotz started (Screen Recording \(self.screenRecording.isGranted ? "granted" : "not granted", privacy: .public))")

        if !settings.hasCompletedOnboarding {
            onboarding.show(step: .welcome)
        }
        runDebugLaunchArguments(DebugLaunchArguments())
    }

    /// Clean shutdown: stop listening, cancel work, clear the stack.
    func stop() {
        log.info("Shotz stopping")
        settingsObserver = nil
        pruneScheduler?.stop()
        hotkeys.shutdown()
        captureTask?.cancel()
        quickAccess.dismissAll()
    }

    func openSettings(tab: SettingsTab? = nil) { settingsWindow.show(tab: tab) }

    /// Launch again from Finder/Spotlight while running (SPEC §1).
    func handleReopen() {
        log.info("Reopened by the user; showing Settings")
        openSettings()
    }

    // MARK: Settings that act live

    private func applySettings() {
        if statusItem.isVisible != settings.showMenuBarIcon {
            statusItem.isVisible = settings.showMenuBarIcon
            log.info("Menu-bar icon \(self.settings.showMenuBarIcon ? "shown" : "hidden", privacy: .public)")
        }
        statusItem.refreshShortcuts()
        let retention = settings.historyRetention
        if let last = lastAppliedRetention, last != retention {
            log.info("Retention changed to \(retention.rawValue, privacy: .public); pruning now")
            pruneHistory()
        }
        lastAppliedRetention = retention
    }

    // MARK: History

    private func startHistoryPruning() {
        pruneHistory()
        let scheduler = HistoryPruneScheduler { [weak self] in
            await self?.pruneHistoryNow()
        }
        scheduler.start()
        pruneScheduler = scheduler
    }

    private func pruneHistory() {
        Task { await pruneHistoryNow() }
    }

    private func pruneHistoryNow() async {
        let removed = await history.prune(retention: settings.historyRetention)
        if removed > 0 { log.info("History prune removed \(removed)") }
        refreshHistoryMenu()
    }

    private func clearHistory() async {
        quickAccess.dismissAll()
        closedCards.removeAll()
        await history.clear()
        refreshHistoryMenu()
    }

    func refreshHistoryMenu() {
        Task {
            let items = await history.recent(limit: 10)
            statusItem.updateHistory(items)
        }
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
                    editingFlow.presentInStack(result)
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
            if let source = debug.editCapture {
                await debugEditCapture(source, forcedID: debug.captureID, options: options)
            }
            if let dir = debug.snapshotUI {
                await DebugUISnapshot.run(self, into: dir)
            }
        }
    }
}
