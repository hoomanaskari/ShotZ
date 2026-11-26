import os
import AppKit
import AppShell
import Foundation
import ShotzCore

/// Capture flow, restore-last-closed and the quick-access delegate.
extension AppCoordinator {
    func handle(_ action: HotkeyAction) {
        log.info("Action \(action.rawValue, privacy: .public) reached AppCoordinator")
        if let mode = action.captureMode {
            capture(mode)
        } else if action == .restoreLastClosed {
            restoreLastClosed()
        }
    }

    func capture(_ mode: CaptureMode) {
        // SPEC §2: a shortcut pressed while a capture runs is ignored.
        guard !isCapturing else {
            log.info("Capture \(String(describing: mode), privacy: .public) ignored: another capture is in progress")
            return
        }
        guard Permissions.hasScreenRecording else {
            showPermissionStep()
            return
        }
        let options = settings.captureOptions(paths: paths)   // carries playSounds → playSound
        captureTask = Task {
            defer { captureTask = nil }
            do {
                guard let result = try await engine.capture(mode, options: options) else {
                    log.info("Capture cancelled")
                    return
                }
                await deliver(result, actions: AfterCaptureActions(settings: settings))
            } catch CaptureError.permissionDenied {
                showPermissionStep()
            } catch CaptureError.busy {
                log.info("Capture ignored: engine busy")
            } catch is CancellationError {
                log.info("Capture cancelled by shutdown")
            } catch {
                log.error("Capture failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    /// After-capture steps (SPEC §3.5): history, stack, then optional copy/save.
    func deliver(_ result: CaptureResult, actions: AfterCaptureActions) async {
        await history.add(result)
        if actions.showQuickAccess { quickAccess.present(result) }
        refreshHistoryMenu()
        if actions.copyToClipboard {
            do { try await exporter.copyToPasteboard(imageAt: result.fileURL) } catch {
                log.error("Auto-copy failed: \(String(describing: error), privacy: .public)")
            }
        }
        if actions.saveToExportFolder {
            do {
                if let url = try await exporter.saveToExportFolder(
                    imageAt: result.fileURL, suggestedName: result.displayName, askDestination: false
                ) {
                    await history.markExported(id: result.id, url: url)
                }
            } catch {
                log.error("Auto-save failed: \(String(describing: error), privacy: .public)")
            }
        }
    }

    func showPermissionStep() {
        log.notice("Screen Recording permission missing; showing the permission step")
        onboarding.show(step: .screenRecording)
    }

    func openLastInEditor() {
        Task {
            guard let last = await history.recent(limit: 1).first else { return }
            editor.openEditor(for: last)
        }
    }

    func reopenFromHistory(_ capture: CaptureResult) {
        closedCards.removeAll { $0.id == capture.id }
        quickAccess.present(capture)
    }

    // MARK: Restore last closed

    var canRestoreLastClosed: Bool {
        closedCards.contains { FileManager.default.fileExists(atPath: $0.fileURL.path(percentEncoded: false)) }
    }

    func restoreLastClosed() {
        while let last = closedCards.popLast() {
            guard FileManager.default.fileExists(atPath: last.fileURL.path(percentEncoded: false)) else { continue }
            log.info("Restoring last closed card")
            quickAccess.present(last)
            return
        }
        log.info("Nothing to restore")
    }

    // MARK: QuickAccessDelegate

    func quickAccess(requestAnnotate capture: CaptureResult) {
        editor.openEditor(for: capture)
    }

    func quickAccess(didClose capture: CaptureResult, deleteFile: Bool) {
        closedCards.removeAll { $0.id == capture.id }
        guard deleteFile else {
            closedCards.append(capture)
            if closedCards.count > Self.closedCardsLimit { closedCards.removeFirst() }
            return
        }
        Task {
            await history.remove(id: capture.id, deleteFile: true)
            refreshHistoryMenu()
        }
    }

    func quickAccess(didExport capture: CaptureResult, to url: URL) {
        log.info("Exported \(capture.displayName, privacy: .public) to \(url.lastPathComponent, privacy: .public)")
        Task { await history.markExported(id: capture.id, url: url) }
    }

    // MARK: Debug

    /// `--debug-edit-capture <png> [--debug-capture-id <uuid>]`: the same
    /// source path maps to the same history id, so a second launch reopens the
    /// same capture (editor document and recorded export included).
    func debugEditCapture(_ source: URL, forcedID: UUID?, options: CaptureOptions) async {
        let id = forcedID ?? DebugCaptureIdentity.id(forSourcePath: source)
        let capture: CaptureResult
        if let existing = await history.reusableCapture(id: id) {
            capture = existing
            log.info("Debug edit capture: reusing \(id.uuidString, privacy: .public)")
        } else {
            do {
                capture = try DebugCaptureImporter.importImage(at: source, options: options, id: id)
            } catch {
                log.error("Debug edit capture failed for \(source.path(percentEncoded: false), privacy: .public): \(String(describing: error), privacy: .public)")
                return
            }
            await history.add(capture)
            refreshHistoryMenu()
            log.info("Debug edit capture: imported \(source.lastPathComponent, privacy: .public) as \(id.uuidString, privacy: .public)")
        }
        editor.openEditor(for: capture)
    }
}
