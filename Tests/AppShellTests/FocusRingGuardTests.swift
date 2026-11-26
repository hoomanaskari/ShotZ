import AppKit
import Foundation
import SwiftUI
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

/// Every AppShell window built from SwiftUI carries ShotzUI's opening focus guard
/// (DESIGN.md "Focus ring: keyboard only"), so it opens with no ring on its first control.
/// Checked structurally: the guard's view is in the hosted hierarchy. Whether a ring really
/// appears needs a key window on screen, which these hermetic tests never create.
@MainActor
struct FocusRingGuardTests {
    static func containsGuard(_ view: NSView) -> Bool {
        String(describing: type(of: view)).contains("OpeningFocusGuardView") || view.subviews.contains(where: containsGuard)
    }

    static func hosted<V: View>(_ view: V, size: CGSize) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = CGRect(origin: .zero, size: size)
        host.layoutSubtreeIfNeeded()
        return host
    }

    func settings() throws -> (SettingsStore, String) {
        let suite = "ShotzFocusGuard-\(UUID().uuidString)"
        return (SettingsStore(defaults: MemoryDefaults(), variant: .production), suite)
    }

    @Test func onboardingOpensWithoutFocusRing() throws {
        let (settings, _) = try settings()
        let model = OnboardingModel(
            settings: settings,
            hotkeys: HotkeyCenter(settings: settings, hotkeysEnabled: false, registrar: FakeRegistrar()),
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/ShotZ.app"), variant: .production),
            screenRecording: ScreenRecordingStatus(check: { false }),
            previousIdentityMigrated: false
        )
        for step in OnboardingStep.allCases {
            model.step = step
            #expect(Self.containsGuard(Self.hosted(OnboardingView(model: model), size: OnboardingView.size)), "step \(step)")
        }
    }

    @Test func everySettingsTabOpensWithoutFocusRing() throws {
        let (settings, _) = try settings()
        let context = SettingsContext(
            settings: settings,
            hotkeys: HotkeyCenter(settings: settings, hotkeysEnabled: false, registrar: FakeRegistrar()),
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/ShotZ.app"), variant: .production),
            screenRecording: ScreenRecordingStatus(check: { true }),
            clearHistory: {}, showOnboarding: { _ in }
        )
        let tabs = SettingsTabViewController(context: context)
        for (index, tab) in SettingsTab.allCases.enumerated() {
            let view = tabs.tabViewItems[index].viewController!.view
            view.frame = CGRect(x: 0, y: 0, width: SettingsTabViewController.paneWidth, height: 600)
            view.layoutSubtreeIfNeeded()
            #expect(Self.containsGuard(view), "tab \(tab)")
        }
    }

    /// Clickable AppShell controls never opt into focus themselves (DESIGN.md: no `.focusable()`).
    @Test func appShellNeverMakesClickableControlsFocusable() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Sources/AppShell")
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        #expect(!files.isEmpty)
        for file in files {
            let source = try String(contentsOf: file, encoding: .utf8)
            #expect(!source.contains(".focusable("), "\(file.lastPathComponent) uses .focusable()")
        }
    }
}
