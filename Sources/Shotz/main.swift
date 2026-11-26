import AppKit

import ShotzCore

// Before anything reads preferences or arguments: the production app ignores every debug hook
// (launch arguments, argument-domain overrides, SHOTZ_* variables); ShotZ Dev keeps them.
DebugHooks.applyAtLaunch()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
