import AppKit
import ImageIO
import ShotzCore
import SwiftUI
import Testing
@testable import ShotzUI

/// The focus ring shows only for keyboard navigation (owner feedback on 0.1.0: a clicked switch kept
/// a thick ring). Events go to a real window that is never shown, through `NSWindow.sendEvent`, the
/// path a click takes inside the app; nothing is posted system-wide.
@MainActor
@Suite(.serialized)
struct FocusRingTests {
    /// One of every AppKit control, in a window.
    struct Fixture {
        let window: NSWindow
        let sheet: GallerySheet
        let controls: [(String, ShotzControlView)]
        /// Controls a click activates without opening a menu or panel.
        var clickable: [(String, ShotzControlView)] { controls.filter { $0.1 is ShotzPopUpButton == false } }
    }

    static func makeFixture(title: String? = nil) -> Fixture {
        _ = NSApplication.shared
        let controls: [(String, ShotzControlView)] = [
            ("Button", ShotzButton(title: "Save", icon: .save, role: .secondary)),
            ("Primary button", ShotzButton(title: "Done", role: .primary)),
            ("Switch", ShotzSwitch(isOn: false, label: "Show icon in the menu bar")),
            ("Checkbox", ShotzCheckbox("Outline")),
            ("Segmented", ShotzSegmentedControl(segments: [.init(title: "Small"), .init(title: "Medium"), .init(title: "Large")], selectedIndex: 0)),
            ("Swatches", ShotzSwatchRow(swatches: [.init(.systemRed, name: "Red"), .init(.systemBlue, name: "Blue"), .init(.systemGreen, name: "Green")], selectedIndex: 0)),
            ("Slider", ShotzSlider(value: 0.4, label: "Opacity")),
            ("Pop-up", ShotzPopUpButton(items: ["PNG", "JPEG"], selectedIndex: 0)),
            ("Tool button", ShotzToolButton(icon: .arrowTool)),
            ("Toggle chip", ShotzToggleChip(title: "Shadow", icon: .shadow, isOn: false)),
            ("Colour well", ShotzColorWell(color: .systemOrange, label: "Colour")),
            ("Glass button", ShotzGlassIconButton(icon: .close)),
        ]
        let sheet = GallerySheet(width: 560, columnWidth: 300)
        if let title { sheet.title(title) }
        for (name, control) in controls { sheet.row(name, [control], height: 40) }
        sheet.finish()
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: sheet.bounds.size),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = sheet
        sheet.layoutSubtreeIfNeeded()
        return Fixture(window: window, sheet: sheet, controls: controls)
    }

    /// Runs `body` with `event` as the event in progress and the window treated as key (a window
    /// that is never shown is never key, and the ring only shows in a key window).
    static func during<T>(_ event: NSEvent?, _ body: () throws -> T) rethrows -> T {
        let savedEvent = ShotzUI.FocusRing.currentEvent, savedKey = ShotzUI.FocusRing.isKeyWindow
        ShotzUI.FocusRing.currentEvent = { event }
        ShotzUI.FocusRing.isKeyWindow = { _ in true }
        defer { ShotzUI.FocusRing.currentEvent = savedEvent; ShotzUI.FocusRing.isKeyWindow = savedKey }
        return try body()
    }

    static func mouse(_ type: NSEvent.EventType, at p: CGPoint, in window: NSWindow) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: p, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }

    static func key(_ code: UInt16, _ chars: String, flags: NSEvent.ModifierFlags = [], in window: NSWindow) -> NSEvent {
        NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                         windowNumber: window.windowNumber, context: nil, characters: chars, charactersIgnoringModifiers: chars,
                         isARepeat: false, keyCode: code)!
    }

    static func tab(in window: NSWindow) -> NSEvent { key(48, "\t", in: window) }

    /// A pointer click on the control's centre, the way `NSWindow` handles a mouse-down: hit-test,
    /// make the hit view first responder only if it accepts (with the click as the current event),
    /// then `mouseDown`; the control's tracking loop gets the mouse-up from a script. (AppKit drops mouse
    /// events sent to a window that isn't on screen, so the test performs those steps itself.)
    static func click(_ control: ShotzControlView) {
        guard let window = control.window, let content = window.contentView else { return }
        let p = control.convert(CGPoint(x: control.bounds.midX, y: control.bounds.midY), to: nil)
        let down = mouse(.leftMouseDown, at: p, in: window)
        // hitTest takes a point in the receiver's superview (here the window frame view: window coordinates).
        guard let hit = content.hitTest(content.superview?.convert(p, from: nil) ?? p) else { return }
        var queue = [mouse(.leftMouseUp, at: p, in: window)]
        let saved = ShotzControlView.nextTrackingEvent
        ShotzControlView.nextTrackingEvent = { _ in queue.isEmpty ? nil : queue.removeFirst() }
        defer { ShotzControlView.nextTrackingEvent = saved }
        during(down) {
            if hit.acceptsFirstResponder { _ = window.makeFirstResponder(hit) }
            hit.mouseDown(with: down)
        }
    }

    /// Focus moved by Tab: AppKit's key-view navigation from the window.
    static func tabTo(_ control: ShotzControlView) {
        guard let window = control.window else { return }
        during(tab(in: window)) { _ = window.makeFirstResponder(control) }
    }

    // MARK: Pointer

    @Test func aPointerClickActivatesButNeverFocusesOrDrawsTheRing() throws {
        let f = Self.makeFixture()
        for (name, control) in f.clickable {
            var actions = 0
            control.onAction = { _ in actions += 1 }
            _ = f.window.makeFirstResponder(nil)
            Self.click(control)
            #expect(actions == 1, "\(name): the click reached the control")
            #expect(f.window.firstResponder !== control, "\(name): a click must not take keyboard focus")
            #expect(Self.during(nil) { !control.showsFocusRing && !control.controlState.isFocused }, "\(name): no ring after a click")
        }
    }

    @Test func everyControlRefusesFocusDuringPointerEventsAndAcceptsItForTab() throws {
        let f = Self.makeFixture()
        let p = CGPoint(x: 10, y: 10)
        for (name, control) in f.controls {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp, .rightMouseDown, .otherMouseDown] {
                #expect(Self.during(Self.mouse(type, at: p, in: f.window)) { !control.acceptsFirstResponder }, "\(name) refuses focus on \(type.rawValue)")
            }
            #expect(Self.during(Self.tab(in: f.window)) { control.acceptsFirstResponder && control.canBecomeKeyView }, "\(name) accepts Tab focus")
        }
    }

    @Test func aClickedSwitchKeepsTheKeyboardWhereItWas() throws {
        let f = Self.makeFixture()
        let (_, other) = f.controls[0]
        Self.tabTo(other)
        let toggle = try #require(f.controls.first { $0.1 is ShotzSwitch }?.1 as? ShotzSwitch)
        Self.click(toggle)
        #expect(toggle.isOn)
        #expect(f.window.firstResponder === other, "the click left keyboard focus on the control that had it")
    }

    // MARK: Keyboard

    @Test func tabFocusDrawsTheRingAndAClickHidesItButKeepsFocus() throws {
        let f = Self.makeFixture()
        for (name, control) in f.controls {
            Self.tabTo(control)
            #expect(f.window.firstResponder === control, "\(name): Tab focuses it")
            #expect(Self.during(nil) { control.showsFocusRing && control.controlState.isFocused }, "\(name): Tab focus shows the ring")
        }
        let toggle = try #require(f.controls.first { $0.1 is ShotzSwitch }?.1)
        Self.tabTo(toggle)
        Self.click(toggle)
        #expect(f.window.firstResponder === toggle, "still focused after the click")
        #expect(Self.during(nil) { !toggle.showsFocusRing }, "a click hides the ring of a keyboard-focused control")
    }

    @Test func theRingIsVisibleInTheDrawing() throws {
        let f = Self.makeFixture()
        let toggle = try #require(f.controls.first { $0.1 is ShotzSwitch }?.1)
        func pixels() -> Data {
            let rep = toggle.bitmapImageRepForCachingDisplay(in: toggle.bounds)!
            toggle.needsDisplay = true
            Self.during(nil) { toggle.cacheDisplay(in: toggle.bounds, to: rep) }
            return Data(bytes: rep.bitmapData!, count: rep.bytesPerRow * rep.pixelsHigh)
        }
        _ = f.window.makeFirstResponder(nil)
        let rest = pixels()
        Self.click(toggle)
        Self.click(toggle) // back to off, as at rest
        #expect(pixels() == rest, "clicked: drawn exactly as at rest (no ring)")
        Self.tabTo(toggle)
        #expect(pixels() != rest, "Tab-focused: the ring is drawn")
    }

    @Test func focusGivenWithoutTheKeyboardShowsNoRing() throws {
        let f = Self.makeFixture()
        let control = f.controls[0].1
        // A window opening (no event, or the shortcut that opened it) or code giving focus.
        for event in [nil, Self.key(43, ",", flags: .command, in: f.window), Self.key(49, " ", in: f.window)] as [NSEvent?] {
            _ = f.window.makeFirstResponder(nil)
            Self.during(event) { _ = f.window.makeFirstResponder(control) }
            #expect(f.window.firstResponder === control)
            #expect(Self.during(nil) { !control.showsFocusRing }, "no ring for focus that did not come from Tab")
        }
    }

    @Test func classifiesEvents() {
        let w = Self.makeFixture().window
        #expect(ShotzUI.FocusRing.isKeyViewNavigation(Self.tab(in: w)))
        #expect(ShotzUI.FocusRing.isKeyViewNavigation(Self.key(48, "\u{19}", flags: .shift, in: w)))
        #expect(!ShotzUI.FocusRing.isKeyViewNavigation(Self.key(49, " ", in: w)))
        #expect(!ShotzUI.FocusRing.isKeyViewNavigation(nil))
        #expect(ShotzUI.FocusRing.isPointer(Self.mouse(.leftMouseDown, at: .zero, in: w)))
        #expect(!ShotzUI.FocusRing.isPointer(Self.tab(in: w)))
    }

    // MARK: SwiftUI windows

    final class Focusable: NSView { override var acceptsFirstResponder: Bool { true } }

    @Test func aSettingsWindowOpensWithoutKeyboardFocus() throws {
        _ = NSApplication.shared
        let pane = ShotzSettingsPane {
            ShotzSettingsSection("Startup") {
                ShotzSettingsRow("Launch at login") { Toggle("", isOn: .constant(true)).toggleStyle(.shotzSwitch).labelsHidden() }
            }
        }
        let host = NSHostingView(rootView: pane)
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 600, height: 200), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let container = NSView(frame: window.contentLayoutRect)
        let stolen = Focusable(frame: CGRect(x: 0, y: 0, width: 10, height: 10))
        host.frame = container.bounds
        container.addSubview(host)
        container.addSubview(stolen)
        window.contentView = container
        host.layoutSubtreeIfNeeded()
        let guardView = try #require(Self.find(OpeningFocusGuardView.self, in: host))
        #expect(guardView.opening)

        // Something (AppKit's or SwiftUI's default focus) took focus as the window opened.
        _ = window.makeFirstResponder(stolen)
        guardView.windowBecameKey()
        #expect(window.firstResponder === window, "the window opens with nothing focused")

        // Becoming key again (switching back from another app) keeps what the user focused.
        _ = window.makeFirstResponder(stolen)
        guardView.windowBecameKey()
        #expect(window.firstResponder === stolen)

        // Closing and reopening counts as opening again.
        NotificationCenter.default.post(name: NSWindow.willCloseNotification, object: window)
        #expect(guardView.opening)
        guardView.windowBecameKey()
        #expect(window.firstResponder === window)
    }

    @Test func textBeingEditedKeepsFocusWhenAWindowOpens() throws {
        _ = NSApplication.shared
        let window = NSWindow(contentRect: CGRect(x: -10_000, y: -10_000, width: 300, height: 100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        let field = NSTextField(string: "Name")
        field.frame = CGRect(x: 10, y: 10, width: 200, height: 24)
        window.contentView?.addSubview(field)
        _ = window.makeFirstResponder(field)
        let editor = window.firstResponder
        #expect(editor is NSText)
        ShotzUI.FocusRing.clearOpeningFocus(in: window)
        #expect(window.firstResponder === editor)
    }

    static func find<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let v = view as? T { return v }
        for s in view.subviews { if let v = find(type, in: s) { return v } }
        return nil
    }
}

/// Before/after evidence for review: SHOTZ_FOCUS_RING_RENDERS=<dir> swift test --filter FocusRingRenders
@MainActor
@Suite(.serialized)
struct FocusRingRenders {
    static var directory: URL? { ProcessInfo.processInfo.environment["SHOTZ_FOCUS_RING_RENDERS"].map { URL(filePath: $0) } }

    static func write(_ image: CGImage, _ name: String) throws {
        guard let dir = directory else { return }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dest = try #require(CGImageDestinationCreateWithURL(dir.appending(path: name) as CFURL, "public.png" as CFString, 1, nil))
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    static func render(_ f: FocusRingTests.Fixture, _ appearance: NSAppearance) -> CGImage {
        FocusRingTests.during(nil) { f.sheet.render(appearance: appearance, scale: 2) }
    }

    /// Every control in the state `prepare` leaves it in, composed on one sheet (only one control
    /// can hold focus at a time, so each is rendered on its own and cut out).
    static func composite(_ title: String, _ appearance: NSAppearance, prepare: (FocusRingTests.Fixture, ShotzControlView) -> Void) throws -> CGImage {
        let f = FocusRingTests.makeFixture(title: title)
        _ = f.window.makeFirstResponder(nil)
        let base = render(f, appearance)
        let ctx = try #require(CGContext(data: nil, width: base.width, height: base.height, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
        ctx.draw(base, in: CGRect(x: 0, y: 0, width: base.width, height: base.height))
        for (_, control) in f.controls {
            prepare(f, control)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.35)) // let the knob / thumb animations finish
            let shot = render(f, appearance)
            let r = control.frame.insetBy(dx: -6, dy: -6)
            let px = CGRect(x: r.minX * 2, y: r.minY * 2, width: r.width * 2, height: r.height * 2)
            if let crop = shot.cropping(to: px) {
                ctx.draw(crop, in: CGRect(x: px.minX, y: CGFloat(base.height) - px.maxY, width: px.width, height: px.height))
            }
            _ = f.window.makeFirstResponder(nil)
            control.stateOverride = nil
        }
        return try #require(ctx.makeImage())
    }

    @Test func renderFocusRingEvidence() throws {
        guard Self.directory != nil else { return }
        _ = NSApplication.shared
        ShotzUI.Palette.accentOverride = GalleryOutput.blue
        defer { ShotzUI.Palette.accentOverride = nil }
        for (name, appearance) in GalleryOutput.appearances {
            // Before: 0.1.0 let a click take focus, and focus always drew the ring.
            try Self.write(Self.composite("Before (0.1.0): each control just clicked with the pointer", appearance) { _, c in
                c.stateOverride = ShotzUI.ControlState(isSelected: c.isSelected, isFocused: true)
            }, "before-appkit-clicked-\(name)@2x.png")
            // After: real in-process clicks.
            try Self.write(Self.composite("After: each control just clicked with the pointer (no ring)", appearance) { _, c in
                if !(c is ShotzPopUpButton) { FocusRingTests.click(c) } // a pop-up click opens its menu
            }, "after-appkit-pointer-clicked-\(name)@2x.png")
            // After: focus moved with Tab.
            try Self.write(Self.composite("After: each control focused with Tab (ring)", appearance) { _, c in
                FocusRingTests.tabTo(c)
            }, "after-appkit-keyboard-focused-\(name)@2x.png")
            try Self.write(Self.settingsWindow(appearance), "after-settings-window-opened-\(name)@2x.png")
        }
    }

    /// The Settings reference pane in a window, after the window "opened" (the opening-focus guard
    /// ran), with the switches toggled as if clicked.
    static func settingsWindow(_ appearance: NSAppearance) throws -> CGImage {
        let host = NSHostingView(rootView: SettingsPaneExample())
        host.appearance = appearance
        let size = host.fittingSize
        let window = NSWindow(contentRect: CGRect(origin: CGPoint(x: -10_000, y: -10_000), size: size), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.appearance = appearance
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        FocusRingTests.find(OpeningFocusGuardView.self, in: host)?.windowBecameKey()
        #expect(window.firstResponder === window)
        let rep = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return try #require(rep.cgImage)
    }
}
