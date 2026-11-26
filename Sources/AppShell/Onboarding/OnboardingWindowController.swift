import os
import AppKit
import ShotzCore
import SwiftUI

/// Onboarding steps (SPEC §8).
public enum OnboardingStep: Int, CaseIterable, Sendable {
    case welcome, screenRecording, systemShortcuts, launchAtLogin
}

/// The small welcome window: shown on first launch and whenever a capture
/// is attempted without Screen Recording permission. Screen Recording status
/// is polled only while this window is on screen.
@MainActor public final class OnboardingWindowController: NSObject, NSWindowDelegate {
    private let model: OnboardingModel
    private var window: NSWindow?
    private let log = ShotzLog.logger("AppShell")

    public init(
        settings: SettingsStore,
        hotkeys: HotkeyCenter,
        loginItem: LoginItemController,
        screenRecording: ScreenRecordingStatus
    ) {
        model = OnboardingModel(settings: settings, hotkeys: hotkeys, loginItem: loginItem, screenRecording: screenRecording)
        super.init()
        model.onFinish = { [weak self] in self?.window?.close() }
    }

    public var isVisible: Bool { window?.isVisible ?? false }
    /// For `--debug-snapshot-ui` only.
    public var debugWindow: NSWindow? { window }
    public var currentStep: OnboardingStep { model.step }

    public func show(step: OnboardingStep = .welcome) {
        model.step = step
        model.reason = step == .screenRecording && model.settings.hasCompletedOnboarding ? .permissionMissing : .welcome
        model.refreshShortcuts()
        if window == nil {
            let hosting = NSHostingController(rootView: OnboardingView(model: model))
            hosting.sizingOptions = [.preferredContentSize]
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable, .fullSizeContentView]
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.title = String(localized: "Welcome to Shotz")
            window.isMovableByWindowBackground = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            WindowPresenter.prepare(window)
            self.window = window
        }
        if window?.isVisible != true {
            model.reopen()
            model.screenRecording.startPolling()
        }
        log.info("Onboarding shown at step \(String(describing: step), privacy: .public)")
        if let window { WindowPresenter.bringToFront(window, name: "Onboarding") }
    }

    public func windowWillClose(_ notification: Notification) {
        model.screenRecording.stopPolling()
        model.finish()
    }
}
