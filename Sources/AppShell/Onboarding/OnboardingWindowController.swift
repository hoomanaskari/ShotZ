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
    private var window: ShellWindow?
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
    /// For `--debug-snapshot-ui` only: one step in its own off-screen window
    /// (never ordered in), in the given appearance.
    public func debugRender(step: OnboardingStep, appearance: NSAppearance.Name = .aqua, scale: CGFloat = 2) async -> Data? {
        let previous = model.step
        model.step = step
        defer { model.step = previous }
        let window = makeWindow(presentsAsNormalRun: true)
        window.appearance = NSAppearance(named: appearance)
        return await OffscreenRenderer.capture(window, scale: scale)
    }

    private func makeWindow(presentsAsNormalRun: Bool = false) -> ShellWindow {
        let window = ShellWindow(contentRect: NSRect(origin: .zero, size: OnboardingView.size),
                                 styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.contentViewController = NSHostingController(rootView: OnboardingView(model: model).environment(\.presentsAsNormalRun, presentsAsNormalRun))
        window.setContentSize(OnboardingView.size)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = String(localized: "Welcome to \(AppVariant.current.displayName)")
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        return window
    }

    public var currentStep: OnboardingStep { model.step }

    public func show(step: OnboardingStep = .welcome) {
        model.step = step
        model.reason = step == .screenRecording && model.settings.hasCompletedOnboarding ? .permissionMissing : .welcome
        model.refreshShortcuts()
        if window == nil {
            let window = makeWindow()
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
