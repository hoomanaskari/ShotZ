import AppKit
import Foundation
import Testing
import ShotzTestSupport
@testable import AppShell
import ShotzCore

@MainActor
struct SettingsWindowTests {
    func makeContext(_ settings: SettingsStore) -> SettingsContext {
        SettingsContext(
            settings: settings,
            hotkeys: HotkeyCenter(settings: settings, hotkeysEnabled: true, registrar: FakeRegistrar()),
            loginItem: LoginItemController(settings: settings, bundleURL: URL(filePath: "/tmp/build/Shotz.app"), variant: .production),
            screenRecording: ScreenRecordingStatus(check: { false }),
            clearHistory: {},
            showOnboarding: { _ in }
        )
    }

    /// Toolbar tabs size the window to each pane (no scrolling), the title
    /// follows the tab, and nothing is ordered on screen.
    @Test func eachTabFitsTheWindowAndNamesIt() {
        let (settings, _) = makeSettings()
        let tabs = SettingsTabViewController(context: makeContext(settings))
        let window = SettingsWindowController.makeWindow(tabs: tabs)
        #expect(tabs.tabStyle == .toolbar)
        #expect(tabs.tabViewItems.map(\.label) == SettingsTab.allCases.map(\.title))
        #expect(tabs.tabViewItems.allSatisfy { $0.image != nil })

        var heights: [SettingsTab: CGFloat] = [:]
        for tab in SettingsTab.allCases {
            tabs.select(tab)
            tabs.fitWindowToSelection(animate: false)
            #expect(window.title == tab.title)
            #expect(window.contentLayoutRect.width == SettingsTabViewController.paneWidth)
            heights[tab] = window.contentLayoutRect.height
        }
        #expect(heights.values.allSatisfy { $0 > 200 })
        #expect(Set(heights.values).count > 1)            // panes are not one fixed size
        #expect(heights[.editor, default: 0] < heights[.general, default: 0])
        #expect(!window.isVisible)
    }

    @Test func commandDigitsSelectTabs() throws {
        let (settings, _) = makeSettings()
        let tabs = SettingsTabViewController(context: makeContext(settings))
        let window = SettingsWindowController.makeWindow(tabs: tabs)
        let event = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                                                  windowNumber: window.windowNumber, context: nil, characters: "3",
                                                  charactersIgnoringModifiers: "3", isARepeat: false, keyCode: 0x14))
        #expect(window.performKeyEquivalent(with: event))
        #expect(tabs.selectedTabViewItemIndex == 2)
    }
}
