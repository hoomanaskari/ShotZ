import os
import AnnotationKit
import AppKit
import ImageIO
import QuartzCore
import ShotzCore

/// Development harness, off unless `SHOTZ_EDITOR_SCRIPT=<file>` is set:
/// replays a small script of real mouse/key events through the editor window
/// (so the same code paths as a person run), takes layer-tree snapshots and
/// measures drag performance. Used to exercise the editor without UI tests.
///
/// Script lines (coordinates are base-image pixels, `#` starts a comment):
///   tool <key>                 press a single-key shortcut (v a r o l t h b n p c g, 1–8)
///   drag x1 y1 x2 y2 [steps] [shift] [option] [command]
///   click x y [shift] [option] [command] [double]
///   type <text>                type into the focused view (text editing)
///   key escape|return|delete|left|right|up|down [shift] [command] [option]
///   cmd <char|return> [shift] [option]   a ⌘ shortcut (menu command, or a key press otherwise)
///   zoom fit|actual|in|out
///   snapshot <path.png>        render the window's layer tree
///   dump <path.json>           write the document JSON
///   bench <x1> <y1> <x2> <y2> <frames>   drag at 60 Hz and log timings
///   background on [1:1|4:3|16:9|3:2] | off
///   export <path.png>          render the flattened document
///   dragfile                   log the drag-out file
///   capture <png> <uuid> <doc.json> [rendered.png]   open through openEditor(for:) and switch to it;
///                              closing it then writes the annotated PNG to rendered.png
///   (paths with spaces: wrap them in "double quotes")
///   hover x y                  move the pointer over the canvas
///   appearance light|dark|system   window appearance
///   panel                      toggle the background panel
///   size <w> <h>               window content size
///   select all|none
///   textstyle <decoration>     the Text tool's decoration for the next text
///   down|move|up x y [mods]    one mouse event (snapshot mid-drag)
///   wait <ms>
@MainActor final class EditorScriptRunner {
    /// The window commands act on (switches when `capture` opens another).
    private var controller: EditorWindowController
    private var lines: [String]
    private let log = ShotzLog.logger("AnnotationEditor")

    static var isScripted: Bool { ProcessInfo.processInfo.environment["SHOTZ_EDITOR_SCRIPT"] != nil }

    /// Starts once per process, on the first editor window.
    static func startIfRequested(for controller: EditorWindowController, coordinator: EditorCoordinator) {
        guard !started else { return }
        guard let path = ProcessInfo.processInfo.environment["SHOTZ_EDITOR_SCRIPT"],
              let text = try? String(contentsOfFile: path, encoding: .utf8) else { return } // no readable script: normal run
        let runner = EditorScriptRunner(controller: controller, script: text)
        runner.coordinator = coordinator
        started = true
        current = runner
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { runner.next() }
    }

    private static var current: EditorScriptRunner?
    private static var started = false
    private weak var coordinator: EditorCoordinator?

    init(controller: EditorWindowController, script: String) {
        self.controller = controller
        lines = script.split(separator: "\n").map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    private var window: NSWindow? { controller.window }

    private func next(after delay: Double = 0.05) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in self?.step() }
    }

    private func step() {
        guard !lines.isEmpty else {
            log.notice("SCRIPT done")
            Self.current = nil
            return
        }
        let line = lines.removeFirst()
        log.notice("SCRIPT \(line, privacy: .public)")
        let parts = Self.tokens(line)
        let args = Array(parts.dropFirst())
        let flags = Self.flags(args)
        let nums = args.compactMap(Double.init).map { CGFloat($0) }
        switch parts.first ?? "" {
        case "tool":
            sendKey(chars: args.first ?? "v", keyCode: 0)
        case "click":
            guard nums.count >= 2 else { break }
            let p = CGPoint(x: nums[0], y: nums[1])
            let count = args.contains("double") ? 2 : 1
            for i in 1...count {
                mouse(.leftMouseDown, p, flags, clickCount: i)
                mouse(.leftMouseUp, p, flags, clickCount: i)
            }
        case "drag":
            guard nums.count >= 4 else { break }
            let steps = nums.count >= 5 ? Int(nums[4]) : 12
            let a = CGPoint(x: nums[0], y: nums[1]), b = CGPoint(x: nums[2], y: nums[3])
            mouse(.leftMouseDown, a, flags)
            dragSteps(from: a, to: b, steps: steps, flags: flags) { [weak self] in
                self?.mouse(.leftMouseUp, b, flags)
                self?.next()
            }
            return
        case "type":
            let text = line.dropFirst(5)
            if let tv = window?.firstResponder as? NSTextView { tv.insertText(String(text), replacementRange: tv.selectedRange()) }
        case "key":
            let codes: [String: UInt16] = ["escape": 53, "return": 36, "delete": 51, "left": 123, "right": 124, "down": 125, "up": 126]
            let chars: [String: String] = [
                "escape": "\u{1b}", "return": "\r", "delete": "\u{7f}",
                "left": String(UnicodeScalar(NSLeftArrowFunctionKey).map(Character.init) ?? " "),
                "right": String(UnicodeScalar(NSRightArrowFunctionKey).map(Character.init) ?? " "),
                "down": String(UnicodeScalar(NSDownArrowFunctionKey).map(Character.init) ?? " "),
                "up": String(UnicodeScalar(NSUpArrowFunctionKey).map(Character.init) ?? " "),
            ]
            let name = args.first ?? "escape"
            sendKey(chars: chars[name] ?? "", keyCode: codes[name] ?? 53, flags: flags)
        case "cmd":
            let c = args.first ?? ""
            sendKeyEquivalent(flags.contains(.shift) ? c.uppercased() : c, flags: flags.union(.command))
        case "zoom":
            switch args.first {
            case "fit": controller.zoomToFit(nil)
            case "actual": controller.zoomToActualSize(nil)
            case "in": controller.zoomIn(nil)
            default: controller.zoomOut(nil)
            }
        case "snapshot":
            if let path = args.first { snapshot(to: URL(filePath: path)) }
        case "dump":
            if let path = args.first {
                do { try controller.store.document.jsonData().write(to: URL(filePath: path)) } catch {
                    log.error("SCRIPT dump failed: \(error.localizedDescription, privacy: .public)")
                }
            }
        case "bench":
            guard nums.count >= 5 else { break }
            bench(from: CGPoint(x: nums[0], y: nums[1]), to: CGPoint(x: nums[2], y: nums[3]), frames: Int(nums[4]), flags: flags)
            return
        case "wait":
            next(after: Double(nums.first ?? 100) / 1000)
            return
        case "background":
            // background on [aspect] | off
            if args.first == "on" {
                var style = BackgroundPresets.defaultStyle
                if let a = args.dropFirst().first, let aspect = AnnotationKit.BackgroundStyle.Aspect(rawValue: a) { style.aspect = aspect }
                controller.model.setBackground(style, interactive: false)
            } else {
                controller.model.setBackground(nil, interactive: false)
            }
        case "export":
            // export <path.png>: the flattened document through DocumentExport (full resolution).
            if let path = args.first {
                do {
                    let tmp = try controller.exporterOut.renderTemporaryPNG(controller.store.document, name: "export")
                    try? FileManager.default.removeItem(atPath: path) // replacing a previous run's file
                    try FileManager.default.copyItem(at: tmp, to: URL(filePath: path))
                } catch { log.error("SCRIPT export failed: \(String(describing: error), privacy: .public)") }
            }
        case "dragfile":
            // The file the drag handle / proxy icon would drag.
            log.notice("SCRIPT dragfile \(self.controller.makeDragFile()?.path(percentEncoded: false) ?? "nil", privacy: .public)")
        case "capture":
            // capture <png> <uuid> <document.json>: the quick-access hand-off, openEditor(for:)
            // with a real CaptureResult and an explicit document location. Later commands act on it.
            if args.count >= 4 {
                let rendered = URL(filePath: args[3])
                coordinator?.renderedURL = { _ in rendered }
            }
            guard args.count >= 3, let id = UUID(uuidString: args[1]),
                  let info = EditorCoordinator.imageInfo(URL(filePath: args[0])) else {
                log.error("SCRIPT capture needs <png> <uuid> <document.json>")
                break
            }
            let capture = CaptureResult(id: id, fileURL: URL(filePath: args[0]), displayName: "ShotZ harness capture", kind: .area,
                                        pixelSize: info.pixelSize, scale: info.scale, displayID: 0)
            if let opened = coordinator?.openEditor(for: capture, documentURL: URL(filePath: args[2])) {
                controller = opened
                log.notice("SCRIPT capture opened with \(opened.store.document.objects.count) objects")
            }
        case "appearance":
            // appearance light|dark|system: the window's appearance (snapshots of both themes).
            switch args.first {
            case "light": window?.appearance = NSAppearance(named: .aqua)
            case "dark": window?.appearance = NSAppearance(named: .darkAqua)
            default: window?.appearance = nil
            }
        case "size":
            // size <w> <h>: the window's content size in points (720 × 480 is the minimum).
            if nums.count >= 2 { window?.setContentSize(NSSize(width: nums[0], height: nums[1])) }
            log.notice("SCRIPT window frame \(NSStringFromRect(self.window?.frame ?? .zero), privacy: .public) min \(NSStringFromSize(self.window?.minSize ?? .zero), privacy: .public) bar fitting \(self.controller.optionsBar.fittingSize.width) content min \(NSStringFromSize(self.window?.contentMinSize ?? .zero), privacy: .public)")
        case "panel":
            // panel: show or hide the background panel.
            controller.toggleBackgroundPanel(nil)
        case "select":
            // select all | none
            if args.first == "all" { controller.model.selectAll() } else { controller.model.clearSelection() }
        case "textstyle":
            // textstyle plain|outlined|solidPill|translucentPill: the Text tool's decoration.
            if let d = args.first.flatMap(TextStyle.Decoration.init(rawValue:)) {
                controller.model.library.update(.text) { $0.textStyle.decoration = d }
            }
        case "down", "move", "up":
            // A drag in separate steps, so a snapshot can be taken mid-drag.
            guard nums.count >= 2 else { break }
            let type: NSEvent.EventType = parts[0] == "down" ? .leftMouseDown : parts[0] == "move" ? .leftMouseDragged : .leftMouseUp
            mouse(type, CGPoint(x: nums[0], y: nums[1]), flags)
        case "hover":
            // hover x y: the pointer moves over the canvas (tracking areas need the window server).
            if nums.count >= 2, let window, let e = NSEvent.mouseEvent(
                with: .mouseMoved, location: windowPoint(CGPoint(x: nums[0], y: nums[1])), modifierFlags: [],
                timestamp: 0, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
            ) { controller.canvas.mouseMoved(with: e) }
        case "close":
            window?.performClose(nil)
        default:
            log.error("SCRIPT unknown command \(line, privacy: .public)")
        }
        next()
    }

    /// Splits a script line on spaces; "double quotes" keep a path with spaces together.
    static func tokens(_ line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var quoted = false
        var hasToken = false
        for ch in line {
            if ch == "\"" {
                quoted.toggle()
                hasToken = true
            } else if ch == " ", !quoted {
                if hasToken { out.append(current) }
                current = ""
                hasToken = false
            } else {
                current.append(ch)
                hasToken = true
            }
        }
        if hasToken { out.append(current) }
        return out
    }

    private static func flags(_ args: [String]) -> NSEvent.ModifierFlags {
        var f: NSEvent.ModifierFlags = []
        if args.contains("shift") { f.insert(.shift) }
        if args.contains("option") { f.insert(.option) }
        if args.contains("command") { f.insert(.command) }
        return f
    }

    // MARK: Events

    private func windowPoint(_ p: CGPoint) -> NSPoint {
        let canvas = controller.canvas
        return canvas.convert(canvas.canvasLayout.toCanvas(p), to: nil)
    }

    private func mouse(_ type: NSEvent.EventType, _ p: CGPoint, _ flags: NSEvent.ModifierFlags, clickCount: Int = 1) {
        guard let window, let event = NSEvent.mouseEvent(
            with: type, location: windowPoint(p), modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: clickCount, pressure: 1
        ) else { return }
        window.sendEvent(event)
    }

    private func dragSteps(from a: CGPoint, to b: CGPoint, steps: Int, flags: NSEvent.ModifierFlags, done: @escaping () -> Void) {
        var i = 0
        func tick() {
            i += 1
            let t = CGFloat(i) / CGFloat(max(steps, 1))
            mouse(.leftMouseDragged, CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + sin(t * .pi) * 0), flags)
            if i < steps {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { tick() }
            } else {
                done()
            }
        }
        tick()
    }

    /// Delivers a key the way AppKit does: with ⌘ or ⌃, the window's key-equivalent pass
    /// first, then keyDown to the first responder if nothing took it.
    private func sendKey(chars: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) {
        guard let window else { return }
        Self.deliverKey(to: window, chars: chars, keyCode: keyCode, flags: flags)
    }

    static func deliverKey(to window: NSWindow, chars: String, keyCode: UInt16, flags: NSEvent.ModifierFlags = []) {
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            guard let e = NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                                           windowNumber: window.windowNumber, context: nil, characters: chars,
                                           charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode) else { continue }
            if type == .keyDown, !flags.intersection([.command, .control]).isEmpty, window.performKeyEquivalent(with: e) { continue }
            window.sendEvent(e)
        }
    }

    /// Finds the editor menu item for a ⌘ shortcut and sends its action down
    /// this window's responder chain (the app may not be active when scripted).
    private func sendKeyEquivalent(_ chars: String, flags: NSEvent.ModifierFlags) {
        let wanted = flags.intersection([.command, .shift, .option])
        func find(_ menu: NSMenu) -> NSMenuItem? {
            for item in menu.items {
                if let sub = item.submenu, let hit = find(sub) { return hit }
                if item.keyEquivalent.lowercased() == chars.lowercased(), item.keyEquivalentModifierMask == wanted { return item }
            }
            return nil
        }
        guard let window else { return }
        guard let item = find(controller.commandMenu), let action = item.action else {
            // Not a menu command (e.g. ⌘Return): deliver it as a key press.
            let keys: [String: (String, UInt16)] = ["return": ("\r", 36), "escape": ("\u{1b}", 53)]
            let (c, code) = keys[chars.lowercased()] ?? (chars, 0)
            sendKey(chars: c, keyCode: code, flags: flags)
            return
        }
        let responder = window.firstResponder ?? window
        if !responder.tryToPerform(action, with: item) { log.error("SCRIPT ⌘\(chars, privacy: .public) not handled") }
    }

    // MARK: Snapshot

    private func snapshot(to url: URL) {
        window?.displayIfNeeded()
        guard let view = window?.contentView?.superview ?? window?.contentView, let layer = view.layer else { return }
        let scale = window?.backingScaleFactor ?? 2
        let size = view.bounds.size
        guard let ctx = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8,
                                  bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return }
        ctx.scaleBy(x: scale, y: scale)
        view.effectiveAppearance.performAsCurrentDrawingAppearance {
            ctx.setFillColor(NSColor.windowBackgroundColor.cgColor)
        }
        ctx.fill(CGRect(origin: .zero, size: size))
        if layer.contentsAreFlipped() || view.isFlipped {
            ctx.translateBy(x: 0, y: size.height)
            ctx.scaleBy(x: 1, y: -1)
        }
        layer.render(in: ctx)
        guard let image = ctx.makeImage(), let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else { return }
        CGImageDestinationAddImage(dest, image, nil)
        CGImageDestinationFinalize(dest)
    }

    // MARK: Bench

    /// Drags at 60 Hz, measuring main-thread time per event and frame pacing.
    private func bench(from a: CGPoint, to b: CGPoint, frames: Int, flags: NSEvent.ModifierFlags) {
        mouse(.leftMouseDown, a, flags)
        var times: [Double] = []
        var i = 0
        let start = CACurrentMediaTime()
        func tick() {
            i += 1
            let t = CGFloat(i) / CGFloat(frames)
            // Zig-zag so strokes are not straight lines.
            let p = CGPoint(x: a.x + (b.x - a.x) * t, y: a.y + (b.y - a.y) * t + sin(t * 40) * 80)
            let t0 = CACurrentMediaTime()
            mouse(.leftMouseDragged, p, flags)
            CATransaction.flush()
            times.append((CACurrentMediaTime() - t0) * 1000)
            if i < frames {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0 / 60) { tick() }
            } else {
                mouse(.leftMouseUp, p, flags)
                let total = CACurrentMediaTime() - start
                let sorted = times.sorted()
                let p50 = sorted[sorted.count / 2], p95 = sorted[min(sorted.count - 1, sorted.count * 95 / 100)]
                log.notice("BENCH \(frames) drag events in \(total, format: .fixed(precision: 2)) s; per-event main-thread ms p50 \(p50, format: .fixed(precision: 2)) p95 \(p95, format: .fixed(precision: 2)) max \(sorted.last ?? 0, format: .fixed(precision: 2)); renders \(self.controller.canvas.layers.renderCount)")
                next(after: 0.4)
            }
        }
        tick()
    }
}
