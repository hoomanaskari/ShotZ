import AppKit
import ShotzCore

/// Debug-only in-process exercise of the stack, started by launching with
/// `-QuickAccessSelfTest <dir>` plus `--debug-present` images. It drives the
/// stack through direct method calls only (no synthetic events, no focus
/// changes), writes panel snapshots and `selftest.txt` into `<dir>`, and
/// logs each check. See the engineer report for what it can't reach.
@MainActor final class StackSelfTest {
    private unowned let qa: QuickAccessController
    private let dir: URL
    private var lines: [String] = []
    private var failures = 0
    /// The oldest presented capture (its file survives the run), reused for rapid presents.
    private var template: CaptureResult?
    /// Stands in for the live focus host for the whole run.
    private let focusRecorder = RecordingFocusHost()

    static func makeIfRequested(controller: QuickAccessController) -> StackSelfTest? {
        guard let path = UserDefaults.standard.string(forKey: "QuickAccessSelfTest"), !path.isEmpty else { return nil }
        return StackSelfTest(controller: controller, dir: URL(filePath: path, directoryHint: .isDirectory))
    }

    private init(controller: QuickAccessController, dir: URL) {
        qa = controller
        self.dir = dir
    }

    func start() {
        Task { await run() }
    }

    // MARK: Helpers

    func check(_ name: String, _ ok: Bool, _ detail: String = "") {
        if !ok { failures += 1 }
        let line = "\(ok ? "PASS" : "FAIL") \(name)\(detail.isEmpty ? "" : " — \(detail)")"
        lines.append(line)
        qa.log.info("SELFTEST \(line, privacy: .public)")
    }

    private func note(_ text: String) {
        lines.append("NOTE \(text)")
        qa.log.info("SELFTEST NOTE \(text, privacy: .public)")
    }

    private func snapshot(_ name: String) {
        for (display, panel) in qa.panels {
            _ = StackDebugSnapshot.render(panel, to: dir.appending(path: "\(name)-\(display).png"))
        }
    }

    func wait(_ ms: Int) async { try? await Task.sleep(for: .milliseconds(ms)) } // never cancelled

    /// Visible cards, newest first, by vertical position.
    var visibleNewestFirst: [CardView] {
        qa.cards.values.filter { !$0.isHidden && !$0.isExiting }.sorted { $0.frame.minY < $1.frame.minY }
    }

    private var newest: CardView? { qa.model.order.last.flatMap { qa.cards[$0] } }

    // MARK: Run

    private func run() async {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) // reported below if snapshots are missing
        await wait(1500) // let the --debug-present batch arrive and settle
        let start = Date()
        template = qa.model.order.first.flatMap { qa.cards[$0] }?.capture
        qa.focus.host = focusRecorder

        checkOrder("initial order")
        let size = CGSize(width: qa.applied.size.width, height: qa.applied.size.height)
        let backdrops = qa.cards.values.map { card in
            (ThumbnailLoader.coverage(pixelSize: card.source.pixelSize, cardSize: size) < ThumbnailLoader.backdropThreshold) == card.hasBackdrop
        }
        let withBackdrop = qa.cards.values.filter(\.hasBackdrop).count
        check("blurred backdrop on letterboxed cards only", !backdrops.isEmpty && backdrops.allSatisfy { $0 }, "\(withBackdrop) of \(backdrops.count) cards")
        snapshot("01-initial")
        await captureExclusion()
        await hoverAndStyle()
        await focusRules()
        if let template { await returnFromEditor(template: template, qa: qa, dir: dir) }
        await drag()
        await saveAndClose()
        await rapid()
        await sizesAndSides()
        await autoClose()

        let summary = "Self-test finished in \(Int(Date().timeIntervalSince(start)))s: \(failures) failure(s)"
        lines.append(summary)
        qa.log.info("SELFTEST \(summary, privacy: .public)")
        let text = lines.joined(separator: "\n") + "\n"
        do {
            try text.write(to: dir.appending(path: "selftest.txt"), atomically: true, encoding: .utf8)
        } catch {
            qa.log.error("SELFTEST cannot write summary: \(error.localizedDescription, privacy: .public)")
        }
        qa.focus.host = qa
        CardView.ignoresRealPointer = false
    }

    func checkOrder(_ name: String) {
        let byPosition = visibleNewestFirst.map(\.capture.id)
        let byModel = Array(qa.model.order.reversed().prefix(byPosition.count))
        check(name, byPosition == byModel && !byPosition.isEmpty, "\(byPosition.count) visible, newest at bottom")
    }

    private func captureExclusion() async {
        guard StackCaptureProbe.requested else { return note("capture exclusion not checked (add -QuickAccessSelfTestCapture YES)") }
        guard let card = newest, let panel = card.window as? NSPanel else { return check("capture probe", false, "no card") }
        guard panel.sharingType == .none else { return note("capture exclusion skipped: -QuickAccessDebug makes the stack shareable") }
        guard let r = await StackCaptureProbe.run(panel: panel, cardFrameInPanel: card.frame, output: dir.appending(path: "capture-probe.png")) else {
            return note("capture exclusion skipped: no Screen Recording permission or capture failed")
        }
        check("capture probe saw its own backdrop", r.backgroundSeen)
        check("system capture does not include the stack", r.backgroundSeen && !r.cardSeen)
        note("region capture PNG has alpha channel: \(r.pngHasAlpha) (area-style capture; kind heuristic checks corners, not the channel)")
    }

    private func hoverAndStyle() async {
        guard let card = newest, let panel = card.window else { return check("hover", false, "no card") }
        card.setHovered(true)
        await wait(250)
        check("hover reveals controls", card.overlay.isRevealed && qa.hoveredCard === card)
        check("hover does not take key focus in self-test", !panel.isKeyWindow)
        check("hover pauses auto-close", qa.timers.values.allSatisfy { !$0.isRunning })
        snapshot("02-hover-system")
        panel.appearance = NSAppearance(named: .aqua)
        await wait(100)
        snapshot("03-hover-light")
        panel.appearance = NSAppearance(named: .darkAqua)
        await wait(100)
        snapshot("04-hover-dark")
        panel.appearance = nil
        card.setHovered(false)
        await wait(250)
        check("unhover hides controls", !card.overlay.isRevealed && qa.hoveredCard == nil)

        card.flash(String(localized: "Copied"), symbol: "checkmark.circle.fill", success: true)
        await wait(200)
        snapshot("05-flash")

        let event = NSEvent.mouseEvent(with: .rightMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                       windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
        let titles = event.flatMap { card.menu(for: $0) }?.items.filter { !$0.isSeparatorItem }.map(\.title) ?? []
        let expected = [CardAction.copy, .save, .annotate, .quickLook, .showInFinder, .copyFilePath, .close, .closeAndDelete, .closeAll].map(\.title)
        check("context menu items", titles == expected, titles.joined(separator: ", "))

        let labels = card.overlay.accessibilityChildren()?.compactMap { ($0 as? NSView)?.accessibilityLabel() } ?? []
        check("VoiceOver button labels", labels.count == 5 && !labels.contains(""), labels.joined(separator: ", "))
        check("VoiceOver card label", card.accessibilityLabel()?.contains("×") == true, card.accessibilityLabel() ?? "")
    }

    /// SPEC §4.3 keys without eating the owner's typing (driven through the same
    /// entry points real events use; the recorder stands in for real key focus).
    private func focusRules() async {
        guard let template else { return note("focus checks skipped: no capture") }
        let rec = focusRecorder
        let clone = CaptureResult(fileURL: template.fileURL, displayName: "Focus test", kind: template.kind,
                                  pixelSize: template.pixelSize, scale: template.scale, displayID: template.displayID)
        qa.present(clone)
        await wait(450)
        guard let card = qa.cards[clone.id] else { return check("focus: card presented", false) }
        let t0 = rec.takes, r0 = rec.releases
        card.setHovered(true) // what the post-layout refresh does for a card under a resting pointer
        await wait(50)
        check("card appearing under a stationary pointer does not take key", rec.takes == t0 && !qa.focus.hasKey)
        qa.cardPointerMoved(card, buttonsDown: true)
        check("no key while a mouse button is down", rec.takes == t0)
        qa.cardPointerMoved(card, buttonsDown: false)
        check("genuine pointer movement takes key", rec.takes == t0 + 1 && qa.focus.hasKey)
        let window = card.window?.windowNumber ?? -1
        let consumed = qa.handleKeyDown(keyCode: 0, characters: "a", modifiers: [], windowNumber: window, isRepeat: false)
        check("unhandled key releases key", !consumed && rec.releases == r0 + 1 && !qa.focus.hasKey)
        qa.cardPointerMoved(card, buttonsDown: false)
        check("key stays released until the pointer leaves and returns", rec.takes == t0 + 1)
        card.setHovered(false)
        card.setHovered(true)
        qa.cardPointerMoved(card, buttonsDown: false)
        check("re-entering and moving takes key again", rec.takes == t0 + 2)
        qa.focus.handle(.spaceChanged)
        check("Space change releases key", rec.releases == r0 + 2)
        card.setHovered(false)
        card.setHovered(true)
        qa.cardPointerMoved(card, buttonsDown: false)
        let esc = qa.handleKeyDown(keyCode: KeyCode.escape, characters: "\u{1b}", modifiers: [], windowNumber: window, isRepeat: false)
        await wait(300)
        check("card shortcut is consumed and closing the hovered card releases key",
              esc && qa.cards[clone.id] == nil && !rec.holdsKey && !qa.focus.hasKey)
    }

    private func drag() async {
        guard let card = newest else { return check("drag", false, "no card") }
        guard let writer = qa.cardDragWriter(card) as? DragFileWriter else { return check("drag writer", false) }
        let url = writer.fileURL
        let config = ExportConfiguration.current()
        check("drag file exists", FileManager.default.fileExists(atPath: url.path(percentEncoded: false)), url.lastPathComponent)
        check("drag file name and format", url.lastPathComponent == "\(card.capture.displayName).\(config.format.fileExtension)")
        // Round-trip through a private pasteboard, the way a drop target reads it.
        let pb = NSPasteboard(name: NSPasteboard.Name("app.shotz.selftest.\(UUID().uuidString)"))
        pb.clearContents()
        pb.writeObjects([writer])
        let readURL = (pb.readObjects(forClasses: [NSURL.self]) as? [URL])?.first
        let types = pb.types ?? []
        check("drag pasteboard file URL", readURL == url)
        let imageType = NSPasteboard.PasteboardType(config.format.utType.identifier)
        let bytes = pb.data(forType: imageType)?.count ?? 0
        check("drag pasteboard image data (promised)", bytes > 0, "\(types.map(\.rawValue)) \(bytes) bytes")
        pb.releaseGlobally()

        let center = card.window.map { $0.convertPoint(toScreen: card.convert(CGPoint(x: card.bounds.midX, y: card.bounds.midY), to: nil)) } ?? .zero
        let screen = card.window?.screen?.frame ?? .zero
        let edge = qa.applied.side == .left ? CGPoint(x: screen.minX + 1, y: screen.midY) : CGPoint(x: screen.maxX - 1, y: screen.midY)
        check("swipe edge detection", qa.card(card, isAtSwipeEdge: edge) && !qa.card(card, isAtSwipeEdge: center))

        let before = qa.cards.count
        qa.card(card, dragEndedWith: .copy, swiped: false)
        await wait(400)
        check("successful drop removes card", qa.cards.count == before - 1 && qa.cards[card.capture.id] == nil)
        checkOrder("order after drop")

        guard let next = newest else { return }
        next.alphaValue = 0.35 // as during a drag
        qa.card(next, dragEndedWith: [], swiped: false)
        await wait(300)
        check("cancelled drag keeps card", qa.cards[next.capture.id] != nil)
        qa.card(next, dragEndedWith: [], swiped: true)
        await wait(400)
        check("swipe off edge dismisses card", qa.cards[next.capture.id] == nil)
        snapshot("06-after-drag")
    }

    private func saveAndClose() async {
        guard let card = newest else { return note("no card left for save/close") }
        let folder = ExportConfiguration.current().exportFolder
        if folder.standardizedFileURL == ShotzPaths.defaultExportFolder.standardizedFileURL {
            note("Save skipped: export folder is the real Desktop; pass -general.exportFolder <dir>")
        } else {
            let before = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).count) ?? 0
            qa.perform(.save, on: card)
            await wait(300)
            snapshot("07-saved-flash")
            await wait(1000)
            let after = (try? FileManager.default.contentsOfDirectory(atPath: folder.path(percentEncoded: false)).count) ?? 0
            check("save writes to export folder", after == before + 1, folder.lastPathComponent)
            let closeAfterSave = qa.settings.quickAccessCloseAfterSave
            check("close-after-save setting honoured", (qa.cards[card.capture.id] == nil) == closeAfterSave)
        }
        guard let victim = newest else { return }
        let file = victim.capture.fileURL
        qa.perform(.closeAndDelete, on: victim)
        await wait(800)
        check("close and delete removes card and file", qa.cards[victim.capture.id] == nil && !FileManager.default.fileExists(atPath: file.path(percentEncoded: false)))
        if let other = newest {
            qa.perform(.close, on: other)
            await wait(400)
            check("close keeps file", qa.cards[other.capture.id] == nil && FileManager.default.fileExists(atPath: other.capture.fileURL.path(percentEncoded: false)))
        }
    }

    private func rapid() async {
        guard let template else { return note("rapid skipped: no capture to clone") }
        var ids: [UUID] = []
        let t0 = CACurrentMediaTime()
        for i in 1...10 {
            let c = CaptureResult(fileURL: template.fileURL, displayName: "Rapid \(i)", kind: template.kind,
                                  pixelSize: template.pixelSize, scale: template.scale, displayID: template.displayID)
            ids.append(c.id)
            qa.present(c)
        }
        let elapsed = (CACurrentMediaTime() - t0) * 1000
        note("10 presents took \(String(format: "%.1f", elapsed)) ms on the main thread")
        await wait(60)
        snapshot("08-rapid-mid")
        await wait(1200)
        snapshot("09-rapid-settled")
        let visible = visibleNewestFirst.map(\.capture.id)
        check("rapid: five newest kept, newest at bottom", visible == Array(ids.suffix(5).reversed()), "\(visible.count) visible of \(qa.cards.count)")
        check("rapid: older cards evicted", qa.cards.count == 5)
        let maxPx = qa.cards.values.compactMap(\.thumbnailPixelSize).map { max($0.width, $0.height) }.max() ?? 0
        check("thumbnails downsampled", maxPx > 0 && maxPx <= qa.applied.size.width * 2 + 2, "largest thumbnail side \(Int(maxPx)) px")
    }


    private func sizesAndSides() async {
        var s = qa.applied
        for size in [CardSize.small, .medium, .large] {
            s.size = size
            qa.apply(s)
            await wait(500)
            let w = visibleNewestFirst.first?.frame.width ?? 0
            check("size \(size.rawValue)", w == size.width, "card width \(w)")
            snapshot("10-size-\(size.rawValue)")
        }
        let original = s.side
        s.side = original == .left ? .right : .left
        qa.apply(s)
        await wait(500)
        let panelX = qa.panels.values.first?.frame.minX ?? -1
        let screen = qa.panels.values.first?.screen?.visibleFrame ?? .zero
        check("side \(s.side.rawValue)", s.side == .left ? panelX == screen.minX.rounded() : panelX > screen.midX)
        s.side = original
        qa.apply(s)
        await wait(400)
        checkOrder("order after size/side changes")
    }

    private func autoClose() async {
        guard let card = newest else { return }
        var s = qa.applied
        s.autoClose = 2
        qa.apply(s)
        await wait(600) // after the post-layout hover refresh, which reads the real pointer
        card.setHovered(true)
        await wait(2600)
        check("auto-close paused while hovering", !qa.cards.isEmpty)
        card.setHovered(false)
        await wait(3000)
        check("auto-close fires after hover ends", qa.cards.isEmpty, "\(qa.cards.count) left")
        s.autoClose = 0
        qa.apply(s)
    }
}
