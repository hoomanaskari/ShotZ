import os
import AppKit
import CoreGraphics
import Foundation
import ShotzCore

/// Permission preflight and System Settings deep links. Never changes
/// system settings itself.
public enum Permissions {
    /// Screen Recording granted (no prompt).
    public static var hasScreenRecording: Bool { CGPreflightScreenCaptureAccess() }

    /// Shows the system prompt (first time only) so Shotz appears in the
    /// Screen Recording list. Returns current state.
    @discardableResult
    public static func requestScreenRecording() -> Bool { CGRequestScreenCaptureAccess() }

    /// Privacy & Security ▸ Screen & System Audio Recording.
    public static let screenRecordingSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )

    /// Keyboard settings (Keyboard Shortcuts… lives there).
    public static let keyboardSettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.Keyboard-Settings.extension"
    )

    @MainActor public static func openScreenRecordingSettings() {
        open(screenRecordingSettingsURL)
    }

    @MainActor public static func openKeyboardSettings() {
        open(keyboardSettingsURL)
    }

    @MainActor private static func open(_ url: URL?) {
        guard let url else { return }
        NSWorkspace.shared.open(url)
    }

    // MARK: Relaunch

    /// Arguments worth keeping across a relaunch: only `--no-hotkeys`
    /// (`--debug-*` actions must not run twice).
    public static func relaunchArguments(from arguments: [String]) -> [String] {
        arguments.dropFirst().contains("--no-hotkeys") ? ["--no-hotkeys"] : []
    }

    /// Quits and reopens this same bundle (macOS often applies a new Screen
    /// Recording grant only to a fresh process).
    @MainActor public static func relaunch(bundleURL: URL = Bundle.main.bundleURL) {
        let args = relaunchArguments(from: DebugHooks.arguments)   // the production app relaunches with none
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        // Wait for this process to exit, then open a new instance of the bundle.
        process.arguments = [
            "-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.1; done; shift; exec /usr/bin/open -n \"$@\"",
            "sh", String(ProcessInfo.processInfo.processIdentifier), bundleURL.path(percentEncoded: false),
        ] + (args.isEmpty ? [] : ["--args"] + args)
        do {
            try process.run()
            ShotzLog.logger("AppShell").notice("Relaunching")
            NSApp.terminate(nil)
        } catch {
            ShotzLog.logger("AppShell").error("Relaunch failed: \(error.localizedDescription, privacy: .private)")
        }
    }
}
