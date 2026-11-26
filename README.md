# ShotZ

ShotZ is an original, open-source macOS screenshot and annotation app. It is a
menu-bar agent: a global shortcut captures the screen, the capture appears in
a quick-access stack of thumbnail cards, and one click opens it in an
annotation editor. It is native Swift 6, AppKit-first, built for macOS 15 and
later, with no telemetry. Its one dependency, Sparkle 2, checks for updates in
the installed app; nothing else uses the network.

- Behaviour: [docs/SPEC.md](docs/SPEC.md)
- Structure, module contracts and conventions: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)

## Phase 1 scope

- Still screenshots: area, window, fullscreen and all-in-one, driven by the
  system `screencapture` tool behind a `CaptureEngine` protocol.
- Global shortcuts ⌘⇧3 / ⌘⇧4 / ⌘⇧5 (rebindable).
- The quick-access stack: copy, save, drag out, annotate, Quick Look, close.
- The annotation editor: arrows, shapes, text, highlighter, blur/pixelate,
  counters, pen, crop and presentation backgrounds, with full undo.
- History of recent captures under `~/Library/Application Support/com.pixelforty.shotz/`.

Out of scope for Phase 1: video/GIF recording, scrolling capture, OCR, cloud
upload, pinning.

The repository currently holds the foundation: the `ShotzCore` contracts,
settings and export service, the `AnnotationKit` document model, and small
working stubs for the other modules wired end to end.

## Build, run, test

Requires Xcode 16 or later (Swift 6 toolchain) on macOS 15 or later.

```bash
swift build                          # debug build of all modules
swift test                           # all unit tests
scripts/bundle.sh dev                # → build/ShotZ Dev.app (development app, debug build)
scripts/bundle.sh release            # → build/ShotZ.app (production app, release build)
scripts/run.sh [app args…]           # build and run ShotZ Dev; quits only its own previous instance
scripts/install.sh                   # production release → /Applications/ShotZ.app (manager/owner only)
swift scripts/make-sample.swift <w> <h> <out.png>   # synthetic test PNG
```

### Debug launch arguments

To exercise the stack and editor without Screen Recording permission, make a
sample image and pass it to the app (`run.sh` passes arguments through and
makes file paths absolute):

```bash
swift scripts/make-sample.swift 5120 2880 build/sample-5k.png
```

```bash
scripts/run.sh --debug-present build/sample-5k.png
```

```bash
scripts/run.sh --debug-edit build/sample-5k.png
```

- `--debug-present <png> [<png>…]` copies each image into the captures folder,
  adds it to history (kind area, scale 2) and shows it in the quick-access stack.
- `--debug-edit <png>` opens the image in the editor.
- `--debug-edit-capture <png>` imports the image into history like
  `--debug-present`, then opens it as a capture (`openEditor(for:)`), so edits
  and Save's export overwrite persist. The same source path always maps to the
  same history entry, so a second launch reopens that capture instead of
  importing again (it is re-imported, under the same id, only if its file is
  gone). `--debug-capture-id <uuid>` forces the id.

### Two apps: ShotZ and ShotZ Dev

There are two builds of the same code, told apart by their bundle id
(`AppVariant` in ShotzCore). They run side by side and never share anything:

| | ShotZ (production) | ShotZ Dev (development) |
|---|---|---|
| Built by | `scripts/bundle.sh release` | `scripts/bundle.sh dev`, `scripts/run.sh` |
| Bundle | `build/ShotZ.app`, installed to `/Applications` | `build/ShotZ Dev.app` |
| Bundle id / preferences | `com.pixelforty.shotz` | `com.pixelforty.shotz.dev` |
| Data | `~/Library/Application Support/com.pixelforty.shotz` | `~/Library/Application Support/com.pixelforty.shotz.dev` |
| Default capture shortcuts | ⌘⇧3 / ⌘⇧4 / ⌘⇧5 | ⌃⌥⌘3 / ⌃⌥⌘4 / ⌃⌥⌘5 |
| Icon / menu-bar glyph | standard | amber DEV band / amber glyph |
| Login item | its own (only from Applications) | its own (off by default) |
| Screen Recording | its own grant | its own grant, given once |

`scripts/run.sh` only ever builds and runs ShotZ Dev, and `scripts/install.sh`
only ever installs ShotZ; neither quits, replaces or unregisters the other.

Rules for engineers and test runs:

- From a git worktree, `scripts/run.sh` starts ShotZ Dev as a **test run**
  (`--no-hotkeys`), executes it directly and keeps it out of Launch Services.
  Every `--debug-*` flag, `-QuickAccessSelfTest` and `SHOTZ_EDITOR_SCRIPT`
  also make a test run. Test runs are hermetic: their own preferences
  (`com.pixelforty.shotz.dev.testrun`) and data (`Application
  Support/com.pixelforty.shotz.dev.testrun`), no shortcuts, no login item, no menu-bar icon, and they never
  open or record the welcome window, so they never touch the owner's ShotZ
  or ShotZ Dev.
- A run exec'd directly from a shell inherits the launcher's Screen Recording
  permission, so "granted" there proves nothing; check through Launch
  Services (`open -n`).
- Never bundle, launch or quit `build/` in the main checkout or anything in
  `/Applications`: those are the owner's.

The launch log starts with `Variant: …` and has one `Hotkey …` line per action
(`registered`, `FAILED (Carbon status …)` or `not registered` with the reason).

Signing: `bundle.sh` uses `$SHOTZ_SIGN_IDENTITY` if set, otherwise the first
"Apple Development" identity in the keychain, otherwise ad-hoc, with the same
rule for debug and release so the Screen Recording grant carries over. A
release build refuses ad-hoc signing unless `SHOTZ_ALLOW_ADHOC=1`, is universal
(arm64 + x86_64), uses the hardened runtime (checked after signing), embeds and
signs Sparkle.framework, and gets a secure timestamp only with a Developer ID
identity. The version comes from `Resources/Info.plist`: change it with
`scripts/bump-version.sh <marketing> [build]`.

`install.sh` (owner/manager, main checkout only; it refuses to run from a
worktree) builds a release, stages and verifies the copy next to
`/Applications/ShotZ.app`, quits only the installed copy (politely, then by
force after 5 s), swaps the new bundle in with two renames (the old copy is
restored if the swap fails) and relaunches ShotZ if it was running.

### App icon

The app icon is the owner's artwork (`Resources/icon-master/owner-artwork-clean.png`) on a generated
macOS tile, set up in `Resources/icon-master/icon.json`. To rebuild it, run:

```bash
scripts/make-icons.sh
```

This writes `Resources/AppIcon.icns` and `Resources/AppIcon-Dev.icns` (with the amber DEV band).
A finished tile master can be used instead: `scripts/make-icons.sh path/to/AppIcon.png`.
Then rebuild the app with `scripts/bundle.sh release`. See [docs/ICON.md](docs/ICON.md).

## Installing

See [docs/INSTALL.md](docs/INSTALL.md): installing into `/Applications`, the
Screen Recording permission, launch at login, freeing ⌘⇧3/4/5 and rolling back.

## Permissions

ShotZ needs **Screen Recording** permission (System Settings ▸ Privacy &
Security ▸ Screen & System Audio Recording). Without it, a capture shows a
prompt explaining how to grant it instead of producing an empty image.
Signing with a stable identity keeps the grant across rebuilds; ad-hoc builds
may need to be re-approved after each rebuild.

For ⌘⇧3/4/5 to reach ShotZ, macOS's own screenshot shortcuts (System Settings
▸ Keyboard ▸ Keyboard Shortcuts ▸ Screenshots) must be turned off. ShotZ only
reads that setting; it never changes system settings.

## License

MIT. See [LICENSE](LICENSE).
