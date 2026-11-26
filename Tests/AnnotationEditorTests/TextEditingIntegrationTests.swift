import AnnotationKit
import AppKit
import Foundation
import ShotzCore
import Testing
@testable import AnnotationEditor

/// Drives a real editor window (never shown) with NSEvents sent to the window itself.
@MainActor
struct TextEditingIntegrationTests {
    private func makeController() throws -> EditorWindowController {
        _ = NSApplication.shared
        let defaults = try #require(UserDefaults(suiteName: "ShotzEditorTests-\(UUID().uuidString)"))
        let ctx = try #require(CGContext(data: nil, width: 800, height: 500, bitsPerComponent: 8, bytesPerRow: 0,
                                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        ctx.setFillColor(CGColor(gray: 0.95, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 500))
        let image = try #require(ctx.makeImage())
        let url = URL(filePath: "/tmp/shotz-editor-test.png")
        let env = EditorEnvironment(
            settings: SettingsStore(defaults: defaults), exporter: DefaultExportService(),
            library: ToolSettingsLibrary(defaults: defaults), backgroundPresets: BackgroundPresets(defaults: defaults),
            openImage: { _ in }, openClipboard: {}
        )
        let doc = AnnotationDocument(baseImageURL: url, pixelSize: CGSize(width: 800, height: 500), scale: 1)
        let controller = EditorWindowController(store: DocumentStore(document: doc), image: image,
                                                base: BaseImageProvider(image: image, url: url), title: "Test", documentURL: nil, env: env)
        controller.model.setTool(.text)
        return controller
    }

    private func key(_ c: EditorWindowController, _ chars: String, _ code: UInt16, _ flags: NSEvent.ModifierFlags = []) throws {
        EditorScriptRunner.deliverKey(to: try #require(c.window), chars: chars, keyCode: code, flags: flags)
    }

    /// Starts a new text with the Text tool and types `text` into the in-place editor.
    private func startTyping(_ c: EditorWindowController, _ text: String) throws -> NSTextView {
        let object = c.model.newTextObject(at: CGPoint(x: 100, y: 100), wrapWidth: nil)
        c.canvas.text.beginEditing(object, isNew: true)
        let tv = try #require(c.window?.firstResponder as? NSTextView)
        tv.insertText(text, replacementRange: tv.selectedRange())
        return tv
    }

    private func texts(_ c: EditorWindowController) -> [String] {
        c.store.document.objects.compactMap { if case .text(let b) = $0.shape { return b.string } else { return nil } }
    }

    @Test func commandReturnCommits() throws {
        let c = try makeController()
        _ = try startTyping(c, "Hello Shotz")
        try key(c, "\r", 36, [.command])
        #expect(!c.canvas.text.isEditingText)
        #expect(texts(c) == ["Hello Shotz"])
    }

    @Test func plainReturnIsANewLineAndEscCommits() throws {
        let c = try makeController()
        _ = try startTyping(c, "One")
        try key(c, "\r", 36)
        #expect(c.canvas.text.isEditingText)
        let tv = try #require(c.window?.firstResponder as? NSTextView)
        tv.insertText("Two", replacementRange: tv.selectedRange())
        try key(c, "\u{1b}", 53)
        #expect(!c.canvas.text.isEditingText)
        #expect(texts(c) == ["One\nTwo"])
    }

    @Test func clickAwayCommits() throws {
        let c = try makeController()
        _ = try startTyping(c, "Click away")
        let window = try #require(c.window)
        window.contentView?.layoutSubtreeIfNeeded()
        c.zoomFit()
        let p = c.canvas.convert(c.canvas.canvasLayout.toCanvas(CGPoint(x: 600, y: 400)), to: nil)
        // A window that was never shown does not dispatch mouse events, so hand the
        // click to the canvas (which owns the click-away rule) directly.
        #expect(window.contentView?.hitTest(p) === c.canvas)
        let down = try #require(NSEvent.mouseEvent(with: .leftMouseDown, location: p, modifierFlags: [], timestamp: 0,
                                                   windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let up = try #require(NSEvent.mouseEvent(with: .leftMouseUp, location: p, modifierFlags: [], timestamp: 0,
                                                 windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        c.canvas.mouseDown(with: down)
        c.canvas.mouseUp(with: up)
        #expect(!c.canvas.text.isEditingText)
        #expect(texts(c) == ["Click away"])
        // The click only committed; it did not place a second, empty text.
        #expect(c.store.document.objects.count == 1)
    }

    @Test func toolKeysTypeWhileEditingAndSwitchToolsAfter() throws {
        let c = try makeController()
        _ = try startTyping(c, "Hello")
        try key(c, "h", 4)
        #expect(c.model.toolKind == .text) // typed, not a shortcut
        try key(c, "\r", 36, [.command])
        #expect(texts(c) == ["Helloh"])
        try key(c, "h", 4)
        #expect(c.model.toolKind == .highlighter)
    }

    @Test func emptyTextIsDiscarded() throws {
        let c = try makeController()
        _ = try startTyping(c, "")
        try key(c, "\u{1b}", 53)
        #expect(c.store.document.objects.isEmpty)
        #expect(!c.store.canUndo)
    }

    @Test func livePreviewShowsTheDecorationWhileTyping() throws {
        let c = try makeController()
        c.model.library.update(.text) { $0.textStyle.decoration = .solidPill }
        let tv = try startTyping(c, "Pill")
        #expect(tv.textColor == .clear) // glyphs come from AnnotationKit's rendering
        let preview = c.canvas.text.previewLayer
        #expect(preview.contents != nil)
        #expect(preview.superlayer === c.canvas.layers.world)
        // The preview covers the whole pill, not just the glyphs.
        guard case .text(var box) = c.model.newTextObject(at: CGPoint(x: 100, y: 100), wrapWidth: nil).shape else { return }
        box.string = "Pill"
        let pill = TextLayout(box: box, fontSize: c.model.style(for: .text).fontSize).frame
        #expect(preview.frame.contains(pill))
        try key(c, "\r", 36, [.command])
        #expect(preview.superlayer == nil)
    }

    @Test func escapeInAnOptionsFieldReturnsTheKeyboardToTheCanvas() throws {
        let c = try makeController()
        c.model.setTool(.crop)
        c.optionsBar.rebuild()
        let field = try #require(c.optionsBar.widthField)
        let window = try #require(c.window)
        window.makeFirstResponder(field)
        #expect(window.firstResponder !== c.canvas)
        window.cancelOperation(nil)
        #expect(window.firstResponder === c.canvas)
    }

    @Test func swatchesAreAccessibleAndPressable() throws {
        var pressed = 0
        let swatch = ColorSwatchControl(color: .systemBlue, selected: true, label: "Blue (5)") { pressed += 1 }
        #expect(swatch.accessibilityRole() == .radioButton)
        #expect(swatch.accessibilityLabel() == "Blue (5)")
        #expect(swatch.accessibilityPerformPress())
        let space = try #require(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
                                                  context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: 49))
        swatch.keyDown(with: space)
        #expect(pressed == 2)
    }

    /// Emoji (with skin tone and a flag) survive in-place editing, the saved document and export.
    @Test func emojiRoundTripsThroughEditingPersistenceAndExport() throws {
        let c = try makeController()
        let emoji = "Ship it 👋🏽🇨🇦"
        _ = try startTyping(c, emoji)
        try key(c, "\r", 36, [.command])
        #expect(texts(c) == [emoji])

        // Persisted document.
        let reloaded = try JSONDecoder().decode(AnnotationDocument.self, from: c.store.document.jsonData())
        guard case .text(let box) = try #require(reloaded.objects.first).shape else { Issue.record("not text"); return }
        #expect(box.string == emoji)
        #expect(box.string.unicodeScalars.count == emoji.unicodeScalars.count)

        // Export: the emoji are laid out (wider than the plain words) and drawn (the image changes).
        let object = try #require(reloaded.objects.first)
        var plain = object
        plain.shape = .text(TextBox(origin: box.origin, wrapWidth: box.wrapWidth, string: "Ship it", style: box.style))
        #expect(TextLayout(box: box, fontSize: object.style.fontSize).frame.width
                > ObjectGeometry.frame(of: plain).width + object.style.fontSize)
        let base = BaseImageProvider(image: try #require(try? c.base.image()), url: reloaded.baseImageURL)
        var withoutEmoji = reloaded
        withoutEmoji.objects = [plain]
        let a = try DocumentExport.data(reloaded, base: base, format: .png, quality: 1, scale: 1)
        let b = try DocumentExport.data(withoutEmoji, base: base, format: .png, quality: 1, scale: 1)
        #expect(!a.isEmpty)
        #expect(a != b)
    }
}
