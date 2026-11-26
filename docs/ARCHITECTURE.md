# ShotZ — architecture

Native Swift 6 (strict concurrency), AppKit-first, macOS 15+. SwiftUI only for
Settings and onboarding. One SwiftPM package, built from the command line and
wrapped into `ShotZ.app` by a script (the product is "ShotZ"; modules,
the `Shotz` executable target, bundle ids and the production data folder keep
their original spelling). No third-party dependencies.

Behaviour is defined in [SPEC.md](SPEC.md). This file defines structure.

## 1. Modules

```
Package.swift
Sources/
  ShotzCore/         shared value types, protocols, settings keys   (foundation; frozen API)
  CaptureKit/        CaptureEngine implementations                  (engineer B)
  QuickAccess/       thumbnail stack overlay                        (engineer B)
  AnnotationKit/     document model, renderer, undo, export         (engineer C)
  AnnotationEditor/  editor window, canvas, toolbar, tools          (engineer D)
  AppShell/          hotkeys, permissions, onboarding, settings UI,
                     status item, launch at login, sounds, history  (engineer A)
  Shotz/             executable: main.swift, AppDelegate, AppCoordinator (engineer A)
Tests/
  <Module>Tests/     one test target per library module (owned with the module)
Resources/           Info.plist, entitlements, AppIcon.icns / AppIcon-Dev.icns, icon-master/, icon generators
scripts/             bundle.sh, run.sh, install.sh, make-icons.sh
docs/
```

Dependency rule (no cycles, nothing sideways):

```
ShotzCore  ←  CaptureKit, QuickAccess, AnnotationKit, AppShell
AnnotationKit  ←  AnnotationEditor
everything  ←  Shotz (executable; the only place modules meet)
```

`QuickAccess` does not import `AnnotationEditor`; `AppShell` imports neither.
All cross-module flow goes through `AppCoordinator` using ShotzCore protocols.

**File ownership is the module directory plus its test directory.** An
engineer never edits another module. A needed change to `ShotzCore` or
`Package.swift` is requested from the engineering manager, who lands it on
`main`; engineers then rebase.

## 2. ShotzCore contracts

```swift
public enum CaptureMode: Sendable { case area, window, fullscreen, allInOne }
public enum CaptureKind: String, Codable, Sendable { case area, window, fullscreen }

/// What every capture hands downstream. The PNG at `fileURL` is the source of truth.
public struct CaptureResult: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public let fileURL: URL          // lossless PNG in the private captures folder
    public let displayName: String   // "ShotZ 2026-11-26 at 10.42.07"
    public let kind: CaptureKind
    public let pixelSize: CGSize     // native pixels
    public let scale: CGFloat        // 2.0 on Retina
    public let displayID: UInt32     // CGDirectDisplayID the capture came from
    public let createdAt: Date
}

public enum CaptureError: Error, Sendable { case permissionDenied, busy, failed(String) }

public protocol CaptureEngine: Sendable {
    /// Runs one capture. Returns nil when the user cancels (Esc).
    func capture(_ mode: CaptureMode, options: CaptureOptions) async throws -> CaptureResult?
}
public struct CaptureOptions: Sendable {
    public var includeWindowShadow: Bool
    public var playSound: Bool
    public var destinationDirectory: URL
    public var fileNamePattern: String
}

/// The overlay. Implemented by QuickAccess.
@MainActor public protocol QuickAccessPresenting: AnyObject {
    var delegate: QuickAccessDelegate? { get set }
    /// imageURL: what the card shows and delivers (annotated render); nil = capture.fileURL.
    func present(_ capture: CaptureResult, imageURL: URL?)   // present(_:) = imageURL nil
    func dismiss(id: CaptureResult.ID)   // programmatic; never calls didClose
    func dismissAll()
}
// Annotate removes the card and calls requestAnnotate, not didClose.
@MainActor public protocol QuickAccessDelegate: AnyObject {
    func quickAccess(requestAnnotate capture: CaptureResult)
    func quickAccess(didClose capture: CaptureResult, deleteFile: Bool)
    func quickAccess(didExport capture: CaptureResult, to url: URL)
}

/// The editor. Implemented by AnnotationEditor.
@MainActor public protocol AnnotationEditing: AnyObject {
    var delegate: AnnotationEditingDelegate? { get set }
    func openEditor(for capture: CaptureResult)
    func openEditor(imageAt url: URL)
}
@MainActor public protocol AnnotationEditingDelegate: AnyObject {
    /// renderedImageURL: flattened full-res PNG (at renderedURL(for:)) when edited, else nil.
    func editor(didClose capture: CaptureResult, renderedImageURL: URL?, onDisplay displayID: UInt32?)
}

/// Shared export behaviour (file naming, format, export folder, pasteboard).
public protocol ExportService: Sendable {
    func copyToPasteboard(imageAt url: URL) async throws
    func saveToExportFolder(imageAt url: URL, suggestedName: String, askDestination: Bool) async throws -> URL?
    func exportFileURLForDrag(imageAt url: URL, suggestedName: String) throws -> URL
}

/// Typed, observable settings over UserDefaults. Keys live in ShotzCore so
/// every module reads the same values; the Settings UI lives in AppShell.
@MainActor public final class SettingsStore: ObservableObject { … }

public protocol HistoryStore: Sendable {
    func add(_ capture: CaptureResult) async
    func recent(limit: Int) async -> [CaptureResult]
    func remove(id: CaptureResult.ID, deleteFile: Bool) async
    func documentURL(for id: CaptureResult.ID) -> URL   // editor's editable document
    func renderedURL(for id: CaptureResult.ID) -> URL   // flattened annotated PNG, next to it
    func exportURL(for id: CaptureResult.ID) async -> URL?
    func markExported(id: CaptureResult.ID, url: URL) async
}
```

`ExportService` has one implementation in ShotzCore (`DefaultExportService`),
used by the stack and the editor so Copy/Save/drag behave identically.

Capture flow (`AppCoordinator`, main actor):

```
hotkey → guard permission → engine.capture(mode) → history.add → sound
       → quickAccess.present(result)
quickAccess.requestAnnotate → editor.openEditor(for:)
editor didClose → quickAccess.present(capture.onDisplay(display), imageURL: rendered)   (SPEC §4.6)
```

`CaptureEditingFlow` (AppShell) holds these routing rules and is the editor's
delegate: opening in the editor from a card, history or the menu dismisses any
card for that capture first; closing returns the card on the editor's display
with the annotated render; other stack presents (history, restore) use the
render when `renderedURL(for:)` exists.

## 3. CaptureKit

- `SystemCaptureEngine`: runs `/usr/sbin/screencapture` via `Process`.
  - area `-i`, window `-i -W`, all-in-one `-i -U`, fullscreen `-D <n>` for
    the display under the pointer; `-o` when shadow is off; `-x` when sounds
    are off (otherwise the system shutter sound is the Phase 1 sound);
    `-t png`, output to a temp name then atomically moved into place.
  - Cancel = process exits and no file exists → return `nil`.
  - One capture at a time (`CaptureError.busy`).
  - Reads pixel size/DPI from the PNG via ImageIO without decoding it.
- Later: `NativeCaptureEngine` on ScreenCaptureKit behind the same protocol.
- Permission checks (`CGPreflightScreenCaptureAccess`) live in AppShell; the
  engine only maps a failure to `.permissionDenied`.

## 4. QuickAccess

- One borderless non-activating `NSPanel` per display that has cards
  (`.nonactivatingPanel`, level `.statusBar`, `canJoinAllSpaces`,
  `fullScreenAuxiliary`, `stationary`, `sharingType = .none` so it never
  appears in captures, `ignoresMouseEvents` outside cards via hit-testing).
- Cards are layer-backed `NSView`s; movement and fades are Core Animation
  springs on `position`/`opacity` only. No Auto Layout in the stack.
- Thumbnails via `CGImageSourceCreateThumbnailAtIndex` off-main, sized to the
  card in device pixels.
- Drag-out with `NSDraggingSource` + `NSFilePromiseProvider`/file URL writer
  using `ExportService.exportFileURLForDrag`; removal on
  `draggingSession(_:endedAt:operation:)` when operation ≠ none.
- Hover keys via a local+global key monitor installed only while the pointer
  is inside a card.
- `StackLayout` (pure struct: screen frame + card sizes → frames) is unit
  tested; the controller is thin.

## 5. AnnotationKit

Value-type document; no AppKit views. This API is the seam between engineers
C and D and is fixed at foundation time.

```swift
public struct AnnotationDocument: Codable, Sendable, Equatable {
    public var baseImageURL: URL
    public var pixelSize: CGSize        // base image, pixels; all geometry is in this space, origin top-left
    public var scale: CGFloat
    public var objects: [AnnotationObject]   // z-order, back to front
    public var crop: CGRect?            // nil = full image
    public var background: BackgroundStyle?
}

public struct AnnotationObject: Identifiable, Codable, Sendable, Equatable {
    public let id: UUID
    public var shape: Shape
    public var style: ObjectStyle       // color, opacity, lineWidth, fill mode, dash, font size…
    public enum Shape: Codable, Sendable, Equatable {
        case arrow(ArrowGeometry)       // start, end, control?, ArrowStyle
        case rectangle(CGRect, cornerRadius: CGFloat)
        case ellipse(CGRect)
        case line(start: CGPoint, end: CGPoint)
        case text(TextBox)              // origin, wrapWidth?, string, TextStyle
        case highlight(HighlightGeometry) // freehand points or rect
        case redact(CGRect, RedactMode) // pixelate | blur | solid, strength
        case counter(CounterGeometry)   // center, tail?, value
        case pen([CGPoint])
    }
}

/// Reference type owning a document plus undo history. Main-actor.
@MainActor public final class DocumentStore: ObservableObject {
    public private(set) var document: AnnotationDocument
    public var canUndo: Bool { get }; public var canRedo: Bool { get }
    public func perform(_ name: String, _ change: (inout AnnotationDocument) -> Void)
    public func beginInteractiveChange(_ name: String)      // drags: many updates,
    public func updateInteractive(_ change: (inout AnnotationDocument) -> Void)
    public func commitInteractiveChange()                   // one undo step
    public func cancelInteractiveChange()
    public func undo(); public func redo()
    public var changes: AsyncStream<DocumentChange> { get } // which object ids changed
}

public enum AnnotationRenderer {
    /// Draws one object. The single source of truth for how objects look;
    /// used by the editor's layers and by export.
    public static func draw(_ object: AnnotationObject, in ctx: CGContext, document: AnnotationDocument, base: BaseImageProvider)
    /// Full flattened image at base-image pixel resolution (× outputScale).
    public static func renderImage(_ document: AnnotationDocument, base: BaseImageProvider, outputScale: CGFloat) throws -> CGImage
    public static func bounds(of object: AnnotationObject) -> CGRect   // dirty rect incl. stroke
}
public enum HitTesting {   // pure geometry, unit-tested
    public static func object(at point: CGPoint, in document: AnnotationDocument, tolerance: CGFloat) -> AnnotationObject.ID?
    public static func handles(for object: AnnotationObject) -> [Handle]
}
public enum DocumentExport {
    public static func write(_ document: AnnotationDocument, to url: URL, format: ImageFormat, quality: Double, scale: CGFloat) throws
}
```

- Undo is snapshot-based: `[AnnotationDocument]` stacks. Documents are small
  values (the base image is a URL), so snapshots are cheap and always correct.
- Redaction (pixelate/blur) uses Core Image on the base image region; results
  are cached by (rect, mode, strength) in `BaseImageProvider`.
- Rendering is Core Graphics in a top-left-origin pixel space; colour space
  follows the base image.
- Persistence: `AnnotationDocument` as JSON at `HistoryStore.documentURL(for:)`.

## 6. AnnotationEditor

- `EditorWindowController` per capture; implements `AnnotationEditing` via
  `EditorCoordinator`.
- Canvas: `NSScrollView` with magnification hosting a layer-backed
  `CanvasView`. Layers:
  1. base image `CALayer` (`contents` = `CGImage`; GPU-composited, never redrawn on edit),
  2. redaction layer (one sublayer per redact object, cached bitmap),
  3. one `CALayer` per annotation object, drawn with
     `AnnotationRenderer.draw` at the current backing scale × zoom (capped),
     redrawn only when that object changes,
  4. selection/handles/guides overlay (`CAShapeLayer`s).
  Dragging an object moves its layer (no redraw). This keeps 5K captures at
  60 fps; nothing ever re-rasterises the full image during interaction.
- Tools are small classes conforming to `protocol Tool { mouseDown/Dragged/Up,
  keyDown, cursor, optionsBar }` that only talk to `DocumentStore`.
- Toolbar/options bar: AppKit (`NSStackView`), original SF Symbols-based icons.
- Export buttons go through `DocumentExport` to a temp file then `ExportService`.

## 7. AppShell and Shotz executable

- `HotkeyCenter`: Carbon `RegisterEventHotKey` through a `HotkeyRegistrar`
  (faked in tests); stored bindings from `SettingsStore` (defaults per
  `AppVariant`), nothing with `--no-hotkeys`. One log line per action.
- `Permissions`: `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`,
  symbolic-hotkey check by *reading* `com.apple.symbolichotkeys` (never writing).
- `StatusItemController`, `SettingsWindow` (SwiftUI), `OnboardingWindow`
  (SwiftUI), `LoginItem` (`SMAppService.mainApp`), `FileHistoryStore`
  (JSON index + captures folder under Application Support).
- `CaptureEditingFlow`: the stack ↔ editor rules of SPEC §4.6 (see §2).
- `AppCoordinator` (in `Shotz`) builds the concrete objects and wires the flow
  in section 2. It is the only file that names concrete types from several modules.

## 8. Build, run, test

```bash
swift build                      # debug build of all modules
swift test                       # all unit tests (must pass before any merge)
scripts/bundle.sh dev            # → build/ShotZ Dev.app (development app, debug build)
scripts/bundle.sh release        # → build/ShotZ.app (production app, release build)
scripts/run.sh [app args…]       # build and run ShotZ Dev; quits only its own previous instance
scripts/install.sh               # production release → /Applications/ShotZ.app (manager/owner only)
scripts/make-icons.sh [<master>] [--glyph <file>]  # app icons (+ menu-bar glyph) from the owner's art; docs/ICON.md
swift Resources/make-app-icon.swift [preview-dir]   # placeholder icon (used when Resources/icon-master/ is empty)
swift Resources/clean-matte.swift <in> <out.png>    # matte clean-up for the artwork cut-out (icon-master/MATTE.md)
swift scripts/make-sample.swift <w> <h> <out.png>   # synthetic test PNG (gradient, shapes, text; 144 dpi)
```

- `run.sh` passes every argument through to the app; arguments that name an
  existing file are made absolute first. From a git worktree it adds
  `--no-hotkeys`, starts the executable directly (not via Launch Services)
  and unregisters the bundle from Launch Services, so worktree copies of
  ShotZ Dev never fight over shortcuts or confuse macOS. A previous instance
  is matched by its resolved executable path. It never touches ShotZ.
- Debug launch arguments (handled in `AppCoordinator.start()`, for exercising
  features without Screen Recording permission):
  - `--debug-present <png> [<png>…]`: copies each image into the captures
    folder, builds a `CaptureResult` (kind area, real pixel size, scale 2, main
    display), adds it to history and presents it in the stack.
  - `--debug-edit <png>`: opens the image in the editor (`openEditor(imageAt:)`).
  - `--debug-edit-capture <png> [--debug-capture-id <uuid>]`: imports the image
    into history as `--debug-present` does and opens it with
    `openEditor(for:)`. The history id is a name-based UUID of the source
    path (`DebugCaptureIdentity`), or the forced id, so a second launch reuses
    the existing entry (`FileHistoryStore.reusableCapture(id:)`) and the
    editor document and recorded export carry over. Re-imported under the same
    id only when the captured file is gone.
  - `--debug-snapshot-ui <dir>`: renders every Settings tab and onboarding
    step to PNGs in `<dir>` off screen (no window is shown and ShotZ is not
    activated), plus the status item when visible and the status menu as text,
    for reviewing the shell UI without clicking through it.
  - Example: `swift scripts/make-sample.swift 5120 2880 build/sample-5k.png &&
    scripts/run.sh --debug-present build/sample-5k.png`. Every `--debug-*`
    flag implies `--no-hotkeys`.

- **App variants** (`ShotzCore/AppVariant.swift`), decided by the bundle id:

  | | `.production` | `.development` |
  |---|---|---|
  | App / bundle id | `ShotZ.app`, `app.shotz.Shotz` | `ShotZ Dev.app`, `app.shotz.Shotz.dev` |
  | Executable | `ShotZ` (SwiftPM product `Shotz`, renamed by `bundle.sh`) | same |
  | Preferences | `UserDefaults.standard` (its own domain) | same, its own domain |
  | Data (`ShotzPaths.default`) | `Application Support/Shotz`, temp `Shotz` | `Application Support/ShotZ Dev`, temp `ShotZ Dev` |
  | Default capture shortcuts | ⌘⇧3/4/5 | ⌃⌥⌘3/4/5 |
  | Launch at login default | on (registers only from Applications) | off (registers wherever it runs) |
  | Icon / glyph | `AppIcon.icns`, template glyph | `AppIcon-Dev.icns` (amber DEV band), amber glyph |

  Each has its own login item and Screen Recording permission (granted once
  for ShotZ Dev). `bundle.sh dev` derives the dev Info.plist from
  `Resources/Info.plist` (bundle id, name, display name) and uses the dev icon.
  The launch log starts with `Variant: …`.
- **Test runs** (`AppVariant.isTestRun`): `--no-hotkeys`, set by `run.sh`
  from worktrees and implied by `--debug-*`, `-QuickAccessSelfTest` and
  `SHOTZ_EDITOR_SCRIPT`. Hermetic: preferences in the suite
  `<bundle id>.testrun` (`AppVariant.preferences`, used by `SettingsStore()`
  and `ExportConfiguration.current()`), data in `Application Support/<name>
  Test Runs` (`ShotzPaths.default`), no shortcuts, no login item, no
  onboarding writes, no menu-bar icon, and one launch log line saying so.
  Argument-domain overrides still apply. Carbon lets two processes register
  the same combo, so test copies never hold shortcuts.
- **Screen Recording observations:** a bundle exec'd directly from a shell
  inherits the launcher's TCC responsibility, so its preflight result says
  nothing about ShotZ's own grant. Check grants by launching through Launch
  Services (`open -n …`), then `lsregister -u` the bundle.
- **Names on disk:** the filesystem is case-insensitive, so `bundle.sh`
  builds under a temporary name and moves the bundle into place (removing
  either spelling first), and `install.sh` replaces `/Applications/Shotz.app`
  or `ShotZ.app` so only `ShotZ.app` remains. Instance matching in the
  scripts accepts the old and new executable names, compared case-insensitively.
- **Rule:** nobody bundles, launches or kills anything in the main checkout's
  `build/` or in `/Applications`: those are the owner's apps.

- Bundle ids `app.shotz.Shotz` / `app.shotz.Shotz.dev`, `LSUIElement = true`, `LSMinimumSystemVersion = 15.0`.
- Signing: `bundle.sh` signs with `$SHOTZ_SIGN_IDENTITY` if set, otherwise the
  first "Apple Development" identity in the keychain, otherwise ad-hoc; the
  same rule for both apps. A stable identity matters: it keeps the
  Screen Recording grant across rebuilds, so a release build refuses ad-hoc
  unless `SHOTZ_ALLOW_ADHOC=1`. Hardened runtime on for release (verified after
  signing), `--timestamp=none` (no network). Version from `Resources/Info.plist`
  (checked). No notarisation, no upload.
- `install.sh`: main checkout only; stages and verifies the release next to
  `/Applications/ShotZ.app`, quits only the installed copy (resolved
  executable path; SIGTERM, then SIGKILL after 5 s), swaps with two renames
  (restores the old copy on failure), relaunches if it was running.
- Not sandboxed (it must spawn `screencapture` and write to the export folder).

## 9. Test strategy

- Unit tests (Swift Testing) for everything pure: `StackLayout`, file naming,
  settings defaults, history index, document mutations and undo/redo,
  hit-testing, renderer geometry, Codable round-trips.
- Renderer golden tests: render small documents and compare against
  checked-in PNGs with a per-pixel tolerance; a 5120×2880 export test asserts
  output size and a time budget.
- `CaptureEngine` is tested through a `FakeCaptureEngine` (in ShotzCore's test
  support) plus argument-building tests for `SystemCaptureEngine`; real
  captures are verified manually (they need Screen Recording permission).
- UI is verified by launching ShotZ Dev from the engineer's own worktree
  (`scripts/run.sh`, which adds `--no-hotkeys`) and exercising it through
  debug flags and off-screen renders before handing over; the manager repeats
  that on review. Shortcut handling is tested with a fake `HotkeyRegistrar`.
- `swift build` must be warning-free.

## 10. Conventions

- Swift 6 language mode, strict concurrency. UI types `@MainActor`; engines
  and stores `Sendable` (actors or immutable). No `@unchecked Sendable`
  without a comment explaining why. No force unwraps outside tests.
- AppKit views in code (no storyboards/xibs). Layer-backed, explicit frames
  in performance-critical UI (stack, canvas).
- `public` only for what another module needs; everything else internal.
- One type per file, file named after the type. No file over ~400 lines.
- Errors are typed and surfaced; never swallowed with `try?` unless the
  failure is genuinely irrelevant (comment why).
- Logging through `os.Logger` (subsystem `app.shotz.Shotz`, category = module).
  No `print`. No analytics, no network.
- User-facing strings via `String(localized:)`; English only for now.
- Original assets only. Never copy icons, sounds, text or layouts from other apps.
- Testing must not disturb the person using the Mac: never post synthetic
  global key or mouse events and never bring ShotZ to the front uninvited;
  drive features through debug launch flags and in-process hooks instead.
- Git: small commits, imperative subject (`QuickAccess: add drag-out`), one
  branch per engineer (`eng/<area>`), rebase on `main`, never push.
